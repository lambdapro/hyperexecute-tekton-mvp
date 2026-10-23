#!/usr/bin/env bash
# Spin up a local kind cluster with Tekton and deploy this MVP.
# Needs: docker (or podman), kind, kubectl. Env: LT_USERNAME, LT_ACCESS_KEY.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${LT_USERNAME:?export LT_USERNAME first}"
: "${LT_ACCESS_KEY:?export LT_ACCESS_KEY first}"

CLUSTER=${CLUSTER:-tekton-hx}
REL=https://infra.tekton.dev/tekton-releases

# No Docker but Podman present: point kind at Podman.
if ! command -v docker >/dev/null && command -v podman >/dev/null; then
  export KIND_EXPERIMENTAL_PROVIDER=podman
fi

if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER"
fi

echo ">> Installing Tekton Pipelines"
kubectl apply -f "$REL/pipeline/latest/release.yaml"
kubectl -n tekton-pipelines wait --for=condition=Available deploy --all --timeout=300s
kubectl -n tekton-pipelines-resolvers wait --for=condition=Available deploy --all --timeout=300s

echo ">> Credentials secret"
kubectl create secret generic hyperexecute-credentials \
  --from-literal=LT_USERNAME="$LT_USERNAME" \
  --from-literal=LT_ACCESS_KEY="$LT_ACCESS_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">> Task + Pipeline"
kubectl apply -f tekton/task-hyperexecute.yaml
kubectl apply -f tekton/pipeline.yaml

echo
echo "Done. Run the pipeline from this folder with:"
echo "  ./scripts/run-pipeline.sh"
