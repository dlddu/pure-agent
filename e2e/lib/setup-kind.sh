#!/usr/bin/env bash
# e2e/lib/setup-kind.sh — Create a kind cluster, install Argo Workflows, and load images.
#
# Usage: ./setup-kind.sh [--cluster-name <name>] [--images <img1,img2,...>]
#
# This script is idempotent — re-running it when the cluster already exists is safe.

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
CLUSTER_NAME="${CLUSTER_NAME:-pure-agent-e2e}"
ARGO_VERSION="${ARGO_VERSION:-v3.6.4}"
ARGO_NAMESPACE="argo"

log()  { echo "[setup-kind] $*" >&2; }
warn() { echo "[setup-kind] WARN: $*" >&2; }
die()  { echo "[setup-kind] ERROR: $*" >&2; exit 1; }

# ── Parse args ──────────────────────────────────────────────────────────────
IMAGES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-name) CLUSTER_NAME="$2"; shift 2 ;;
    --images)       IMAGES="$2";       shift 2 ;;
    *)              die "Unknown argument: $1" ;;
  esac
done

# ── Prerequisites ───────────────────────────────────────────────────────────
command -v kind    >/dev/null 2>&1 || die "kind is not installed"
command -v kubectl >/dev/null 2>&1 || die "kubectl is not installed"

# ── Create cluster (idempotent) ─────────────────────────────────────────────
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "Cluster '$CLUSTER_NAME' already exists — skipping creation"
else
  log "Creating kind cluster '$CLUSTER_NAME'"
  kind create cluster --name "$CLUSTER_NAME" --wait 60s
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 \
  || die "Cannot connect to cluster 'kind-${CLUSTER_NAME}'"

# ── Install Argo Workflows ──────────────────────────────────────────────────
if kubectl get namespace "$ARGO_NAMESPACE" >/dev/null 2>&1; then
  log "Namespace '$ARGO_NAMESPACE' already exists — skipping Argo install"
else
  log "Installing Argo Workflows ${ARGO_VERSION}"
  kubectl create namespace "$ARGO_NAMESPACE"
  kubectl apply -n "$ARGO_NAMESPACE" \
    -f "https://github.com/argoproj/argo-workflows/releases/download/${ARGO_VERSION}/quick-start-minimal.yaml"
  log "Waiting for Argo server to be ready"
  kubectl -n "$ARGO_NAMESPACE" rollout status deployment/argo-server --timeout=120s || warn "Argo server rollout timed out"
fi

# ── Load images ─────────────────────────────────────────────────────────────
if [ -n "$IMAGES" ]; then
  IFS=',' read -ra IMAGE_LIST <<< "$IMAGES"
  for img in "${IMAGE_LIST[@]}"; do
    if docker image inspect "$img" >/dev/null 2>&1; then
      log "Loading image '$img' into cluster"
      kind load docker-image "$img" --name "$CLUSTER_NAME"
    else
      warn "Image '$img' not found locally — skipping"
    fi
  done
fi

log "Setup complete: cluster='$CLUSTER_NAME'"
