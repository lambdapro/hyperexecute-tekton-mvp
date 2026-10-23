#!/usr/bin/env bash
# Check (and prepare) everything setup-local.sh needs: a container runtime
# (Docker, or a rootful Podman machine), kind, kubectl and credentials.
# Missing tools are only installed when INSTALL=1; otherwise the command is shown.
set -euo pipefail

ok()   { echo "  ok    $*"; }
fail() { echo "  MISS  $*"; MISSING=1; }
MISSING=0

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  Darwin)               OS=macos ;;
  *)                    OS=linux ;;
esac

install_hint() {  # $1 = winget id, $2 = brew name
  case "$OS" in
    windows) echo "winget install -e --id $1" ;;
    macos)   echo "brew install $2" ;;
    linux)   echo "see https://kind.sigs.k8s.io / https://kubernetes.io/docs/tasks/tools/ / https://podman.io" ;;
  esac
}

need() {  # $1 = command, $2 = winget id, $3 = brew name
  if command -v "$1" >/dev/null; then ok "$1"; return; fi
  local cmd; cmd=$(install_hint "$2" "$3")
  if [ "${INSTALL:-0}" = "1" ] && [ "$OS" != linux ]; then
    echo "  ..    installing $1: $cmd"; $cmd
    command -v "$1" >/dev/null && ok "$1" || fail "$1 installed; open a new terminal so it is on PATH"
  else
    fail "$1 not found. Install: $cmd   (or rerun with INSTALL=1)"
  fi
}

echo ">> Tools"
need kind    Kubernetes.kind    kind
need kubectl Kubernetes.kubectl kubectl

echo ">> Container runtime"
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  ok "docker is running"
elif command -v podman >/dev/null; then
  if [ "$OS" != linux ]; then
    if [ -z "$(podman machine list --format '{{.Name}}' 2>/dev/null)" ]; then
      echo "  ..    creating rootful Podman machine (first time downloads an image)"
      podman machine init --rootful --cpus "${PODMAN_CPUS:-4}" --memory "${PODMAN_MEMORY:-8192}"
    fi
    if ! podman machine list --format '{{.Running}}' | grep -q true; then
      echo "  ..    starting Podman machine"
      podman machine start
    fi
  fi
  if [ "$(podman info --format '{{.Host.Security.Rootless}}')" = "true" ]; then
    if [ "$OS" != linux ]; then
      echo "  ..    switching Podman machine to rootful (kind needs it)"
      podman machine stop && podman machine set --rootful && podman machine start
    else
      fail "Podman is rootless; kind needs rootful podman (run setup-local.sh with sudo)"
    fi
  fi
  ok "podman is running (rootful); kind will use it via KIND_EXPERIMENTAL_PROVIDER=podman"
else
  if command -v docker >/dev/null; then
    fail "docker is installed but not running. Start Docker Desktop"
  else
    fail "no Docker or Podman. Install Podman: $(install_hint RedHat.Podman podman)"
  fi
fi

echo ">> Credentials"
[ -n "${LT_USERNAME:-}" ]   && ok "LT_USERNAME"   || fail "LT_USERNAME   export LT_USERNAME=<your TestMu AI username>"
[ -n "${LT_ACCESS_KEY:-}" ] && ok "LT_ACCESS_KEY" || fail "LT_ACCESS_KEY read -s LT_ACCESS_KEY && export LT_ACCESS_KEY"

echo
if [ "$MISSING" = 1 ]; then
  echo "Fix the MISS lines above, then rerun this script."
  exit 1
fi
echo "All set. Next: ./scripts/setup-local.sh && ./scripts/run-pipeline.sh"
