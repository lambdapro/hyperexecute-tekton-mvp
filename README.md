# HyperExecute × Tekton — MVP

Trigger TestMu AI **HyperExecute** test jobs from a **Tekton** pipeline.
No plugin needed: a reusable Tekton `Task` downloads the HyperExecute CLI and
runs `hyperexecute --config hyperexecute.yaml`. The TaskRun passes or fails
with the HyperExecute job.

Everything runs on your machine: a local Kubernetes cluster (kind, on Podman
or Docker, your choice) with Tekton installed. `run-pipeline.sh` copies this folder into the cluster.

```
run-pipeline.sh ──▶ PipelineRun
                      └─ run-tests    (hyperexecute Task)
                           └─ hyperexecute CLI ──▶ HyperExecute VMs (autosplit x3)
                                                     └─ Selenium tests on TestMu AI grid
```

## Repo layout

| Path | What it is |
|---|---|
| `tests/` | 3 Selenium + pytest tests (sample todo app) |
| `hyperexecute.yaml` | HyperExecute job: autosplit, retries, caching, report upload |
| `tekton/task-hyperexecute.yaml` | **Reusable Task** that runs the HyperExecute CLI |
| `tekton/pipeline.yaml` | Pipeline that runs the Task |
| `tekton/Containerfile` | Pre-baked CLI image for scale |
| `scripts/setup-prereqs.sh` | Checks tools and credentials, prepares Podman or checks Docker |
| `scripts/setup-local.sh` | Creates the kind cluster, installs Tekton, deploys the Task + Pipeline |
| `scripts/run-pipeline.sh` | Triggers the pipeline and streams the HyperExecute logs |

## Prerequisites

### Step 1 — Install the tools (one time)

Pick **one** container runtime, Podman or Docker:

| Tool | Windows | macOS |
|---|---|---|
| **Option A:** Podman | `winget install -e --id RedHat.Podman` | `brew install podman` |
| **Option B:** Docker Desktop | `winget install -e --id Docker.DockerDesktop` | `brew install --cask docker` |
| kind | `winget install -e --id Kubernetes.kind` | `brew install kind` |
| kubectl | `winget install -e --id Kubernetes.kubectl` | `brew install kubectl` |
| bash | Git Bash (part of Git for Windows) | built in |

- **Windows:** Podman and Docker Desktop both run in WSL2. If `wsl --status` says WSL is missing,
  run `wsl --install` and reboot.
- Open a **new terminal** after installing so the tools are on `PATH`.
- On Windows, run every command below in **Git Bash**.

### Step 2 — Set your TestMu AI credentials

```bash
export LT_USERNAME=<your TestMu AI username>
read -s LT_ACCESS_KEY && export LT_ACCESS_KEY      # paste the key, it is not shown
```

Set these in every new terminal. Never put the key in a file.

### Step 3 — Run the prerequisites script

```bash
./scripts/setup-prereqs.sh
```

It checks for kind and kubectl, checks that the credentials are set, and
checks the container runtime:

- **Docker:** Docker Desktop must be running (start it from the Start menu /
  Applications). Nothing else to set up.
- **Podman:** the script gets it ready:
  - creates the Podman machine if there isn't one (rootful, 4 CPUs / 8 GB;
  change with `PODMAN_CPUS` / `PODMAN_MEMORY`)
  - starts the machine if it is stopped
  - switches it to rootful if needed (kind only works with rootful Podman)

Any missing tool is listed with its install command, or run
`INSTALL=1 ./scripts/setup-prereqs.sh` to install it for you.
The script ends with `All set` when everything is ready.

Doing the Podman part by hand instead:

```bash
podman machine init --rootful --cpus 4 --memory 8192   # first time only
podman machine start                                   # after every reboot
```

### Step 4 — Create the cluster and install Tekton (one time)

```bash
./scripts/setup-local.sh
```

This creates the kind cluster `tekton-hx`, installs Tekton, stores
your credentials in the secret `hyperexecute-credentials`, and deploys the
Task and Pipeline. It is safe to rerun.

Which runtime it uses: Docker if Docker is installed, otherwise Podman. If you
have both installed and want Podman, run
`export KIND_EXPERIMENTAL_PROVIDER=podman` first.

Check it worked:

```bash
kubectl get task hyperexecute
kubectl get pipeline hyperexecute-pipeline
```

## Trigger the pipeline

### Step 5 — Run it

```bash
./scripts/run-pipeline.sh
```

What happens:

1. This folder is copied into a volume in the cluster.
2. A Tekton PipelineRun starts and runs the `hyperexecute` Task.
3. The Task downloads the HyperExecute CLI and starts the HyperExecute job.
4. The CLI log streams to your terminal while the tests run.

### Step 6 — Check the result

The run ends with the PipelineRun status and the job link:

```
NAME                     SUCCEEDED   REASON      ...
hyperexecute-run-xxxxx   True        Succeeded   ...
HyperExecute job: https://hyperexecute.lambdatest.com/hyperexecute/task?jobId=...
```

- Exit code `0` = all tests passed; `1` = the job or a test failed.
- Open the job link to see each test's result, video and logs. The job also
  shows on the HyperExecute dashboard (labels `tekton`, `mvp`, `selenium-python`).
- Test reports (JUnit XML) are downloaded into the run's volume under `artifacts/`.
- All runs: `kubectl get pipelineruns`. Details of one run:
  `kubectl describe pipelinerun <name>`.

Rerun any time with `./scripts/run-pipeline.sh`. After a reboot, start your
runtime first: `podman machine start` (Podman) or open Docker Desktop (Docker).

### The command that triggers the HyperExecute job

The Task step in `tekton/task-hyperexecute.yaml` runs:

```bash
hyperexecute --user "$LT_USERNAME" --key "$LT_ACCESS_KEY" \
  --config hyperexecute.yaml --download-artifacts
```

- `LT_USERNAME` / `LT_ACCESS_KEY` come from the `hyperexecute-credentials` secret.
- `--config` is the Task's `config` param; `--download-artifacts` is its
  `extra-args` default.
- The CLI's exit code decides whether the TaskRun passes. The job link it
  prints becomes the `job-url` result.

The same command works without Tekton, from this folder:

```bash
# Linux CLI. macOS: .../darwin/hyperexecute   Windows: .../windows/hyperexecute.exe
curl -fsSL -o hyperexecute https://downloads.lambdatest.com/hyperexecute/linux/hyperexecute
chmod +x hyperexecute
./hyperexecute --user "$LT_USERNAME" --key "$LT_ACCESS_KEY" --config hyperexecute.yaml
```

## Cleanup

Docker:

```bash
kind delete cluster --name tekton-hx
```

Podman:

```bash
KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name tekton-hx   # remove the cluster
podman machine stop                                                      # stop the Podman VM
```

With Podman, `setup-local.sh` sets `KIND_EXPERIMENTAL_PROVIDER=podman` for
you. Set it yourself (`export KIND_EXPERIMENTAL_PROVIDER=podman`) when you run
`kind` commands by hand.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `kind create cluster` fails (Docker) | Docker Desktop not running or out of resources: start or restart it |
| `kind create cluster` fails, or `No kind clusters found` (Podman) | Podman machine stopped or rootless: rerun `./scripts/setup-prereqs.sh` |
| `Cannot connect to Podman` after a reboot | `podman machine start` |
| `Cannot connect to the Docker daemon` | Start Docker Desktop |
| `tar: can't change directory to 'C:/.../src'` | Git Bash rewrote a Linux path. `run-pipeline.sh` sets `MSYS_NO_PATHCONV=1`; do the same in your own `kubectl exec` commands |
| Tekton `wait ... timed out` | Slow image pulls: rerun `./scripts/setup-local.sh` |
| Loader pod stuck `Pending` | `kubectl get sc` should list `standard`; otherwise delete and recreate the cluster |
| CLI: unauthorized / 401 | Wrong or rotated key: re-export `LT_ACCESS_KEY`, rerun `./scripts/setup-local.sh`, then `./scripts/run-pipeline.sh` |
| Pipeline runs but tests fail | Real test failures: open the job link for each test's error |

## Task parameters

| Param | Default | Notes |
|---|---|---|
| `config` | `hyperexecute.yaml` | Path inside the workspace |
| `credentials-secret` | `hyperexecute-credentials` | Keys `LT_USERNAME`, `LT_ACCESS_KEY` |
| `image` | `debian:bookworm-slim` | Use the `tekton/Containerfile` image at scale |
| `cli-url` | Linux CLI download | Skipped if image has `/usr/local/bin/hyperexecute` |
| `extra-args` | `--download-artifacts` | Any other CLI flags |

Results: `job-url`, `exit-code`.

## Rolling out to many teams

- **One shared Task, per-team YAML.** Publish `task-hyperexecute.yaml` once
  (in a shared namespace, or as an OCI Tekton bundle). Teams reference it and
  only own their `hyperexecute.yaml`.
- **Bake the CLI** into an internal image
  (`podman build -f tekton/Containerfile .` or
  `docker build -f tekton/Containerfile .`): no download per run, pinned
  version, faster steps.
- **Per-team secrets** via `credentials-secret`, so each team can map to its
  own TestMu AI user or sub-org.

## Notes

- Behind a corporate proxy, test against internal apps with HyperExecute's
  tunnel (`tunnel: true` in the YAML).
- `job-url` is read from the CLI output (best effort); the exit code is what
  decides pass or fail.
