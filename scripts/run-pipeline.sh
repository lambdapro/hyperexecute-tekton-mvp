#!/usr/bin/env bash
# Copy this folder into the cluster, start the Tekton PipelineRun, stream the
# HyperExecute logs, and exit with the pipeline's status.
set -euo pipefail
cd "$(dirname "$0")/.."

PVC=hx-src-$(date +%s)

echo ">> Copying $(pwd) into the cluster"
kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC}
  labels: {app: hx-src}
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: ${PVC}-loader
  labels: {app: hx-src}
spec:
  restartPolicy: Never
  containers:
    - name: loader
      image: busybox:1.36
      command: ["sh", "-c", "sleep 600"]
      volumeMounts:
        - {name: src, mountPath: /src}
  volumes:
    - name: src
      persistentVolumeClaim: {claimName: ${PVC}}
YAML
kubectl wait --for=condition=Ready "pod/${PVC}-loader" --timeout=180s >/dev/null
tar cf - --exclude=.git --exclude=reports --exclude=__pycache__ --exclude=.pytest_cache . \
  | MSYS_NO_PATHCONV=1 kubectl exec -i "${PVC}-loader" -- tar xf - -C /src  # Git Bash: keep /src as-is
kubectl delete pod "${PVC}-loader" --wait=true >/dev/null

PR=$(kubectl create -o jsonpath='{.metadata.name}' -f - <<YAML
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: hyperexecute-run-
spec:
  pipelineRef:
    name: hyperexecute-pipeline
  workspaces:
    - name: shared
      persistentVolumeClaim:
        claimName: ${PVC}
YAML
)
echo ">> PipelineRun: ${PR}"

status() { kubectl get pipelinerun "$PR" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || true; }

# Wait for the HyperExecute step pod, then stream its logs.
pod=""
for _ in $(seq 1 120); do
  pod=$(kubectl get pods -l "tekton.dev/pipelineRun=${PR},tekton.dev/pipelineTask=run-tests" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [ -n "$pod" ] && break
  [ "$(status)" = "False" ] && break
  sleep 5
done

if [ -n "$pod" ]; then
  kubectl wait --for=condition=Ready=true "pod/$pod" --timeout=300s >/dev/null 2>&1 || true
  kubectl logs -f "$pod" -c step-run-hyperexecute || true
fi

# Wait for the PipelineRun to finish.
while [ "$(status)" = "Unknown" ] || [ -z "$(status)" ]; do sleep 5; done

echo
kubectl get pipelinerun "$PR"
echo "HyperExecute job: $(kubectl get pipelinerun "$PR" -o jsonpath='{.status.results[?(@.name=="job-url")].value}')"

if [ "$(status)" != "True" ]; then
  echo ">> PipelineRun failed; task logs:"
  kubectl logs -l "tekton.dev/pipelineRun=${PR}" --all-containers --tail=100 || true
  exit 1
fi
