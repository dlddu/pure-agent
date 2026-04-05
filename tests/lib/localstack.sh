#!/usr/bin/env bash
# tests/lib/localstack.sh — LocalStack S3 deployment and assertion helpers
#
# Deploys LocalStack as a Kubernetes Deployment + Service in the test namespace
# for S3 transcript upload verification in Integration and E2E tests.
#
# Functions:
#   deploy_localstack       — Create LocalStack Deployment + Service
#   wait_localstack         — Wait for LocalStack to be ready
#   create_s3_test_bucket   — Create the test S3 bucket
#   teardown_localstack     — Remove LocalStack resources
#   localstack_endpoint_url — Return the in-cluster LocalStack S3 endpoint URL
#   list_s3_objects         — List objects in the test bucket (debug helper)
#   assert_s3_object_exists — Assert a specific S3 key exists
#   assert_s3_transcript_exists     — Assert transcript files exist in S3
#
# Required variables (set by the calling script):
#   NAMESPACE      — Kubernetes namespace
#   KUBE_CONTEXT   — kubectl context
#
# Optional variables:
#   LOCALSTACK_IMAGE    — LocalStack image (default: localstack/localstack:3.8)
#   S3_TEST_BUCKET      — Test bucket name (default: pure-agent-e2e-transcripts)
#   LOCALSTACK_TIMEOUT  — Readiness wait timeout (default: 120s)

set -euo pipefail

# ── Source guard ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--source-only" ]]; then
  true
fi

LOCALSTACK_IMAGE="${LOCALSTACK_IMAGE:-localstack/localstack:3.8}"
S3_TEST_BUCKET="${S3_TEST_BUCKET:-pure-agent-e2e-transcripts}"
LOCALSTACK_TIMEOUT="${LOCALSTACK_TIMEOUT:-120s}"

# ── Logging ──────────────────────────────────────────────────────────────────
_ls_log()  { echo "[localstack] $*" >&2; }
_ls_warn() { echo "[localstack] WARN: $*" >&2; }
_ls_fail() { echo "FAIL $*" >&2; return 1; }

# ── deploy_localstack ────────────────────────────────────────────────────────
# Creates a LocalStack Deployment + Service in the test namespace.
deploy_localstack() {
  local namespace="${NAMESPACE:-pure-agent}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-integration}"

  _ls_log "Deploying LocalStack (image=$LOCALSTACK_IMAGE) in namespace=$namespace"

  kubectl apply -f - -n "$namespace" --context "$kube_context" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: localstack
  labels:
    app: localstack
spec:
  replicas: 1
  selector:
    matchLabels:
      app: localstack
  template:
    metadata:
      labels:
        app: localstack
    spec:
      containers:
        - name: localstack
          image: ${LOCALSTACK_IMAGE}
          ports:
            - containerPort: 4566
          env:
            - name: SERVICES
              value: "s3"
            - name: EAGER_SERVICE_LOADING
              value: "1"
            - name: DEBUG
              value: "0"
          readinessProbe:
            httpGet:
              path: /_localstack/health
              port: 4566
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 3
          resources:
            requests:
              memory: 256Mi
              cpu: 250m
            limits:
              memory: 512Mi
              cpu: 500m
---
apiVersion: v1
kind: Service
metadata:
  name: localstack
  labels:
    app: localstack
spec:
  selector:
    app: localstack
  ports:
    - port: 4566
      targetPort: 4566
      protocol: TCP
  type: ClusterIP
EOF

  _ls_log "LocalStack Deployment + Service created"
}

# ── wait_localstack ──────────────────────────────────────────────────────────
# Waits for the LocalStack pod to be ready.
wait_localstack() {
  local namespace="${NAMESPACE:-pure-agent}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-integration}"

  _ls_log "Waiting for LocalStack to be ready (timeout=$LOCALSTACK_TIMEOUT)"

  kubectl wait deployment/localstack \
    --for=condition=Available \
    -n "$namespace" \
    --context "$kube_context" \
    --timeout="$LOCALSTACK_TIMEOUT" >&2 \
    || { _ls_fail "LocalStack deployment did not become available within $LOCALSTACK_TIMEOUT"; return 1; }

  _ls_log "LocalStack is ready"
}

# ── localstack_endpoint_url ──────────────────────────────────────────────────
# Returns the in-cluster endpoint URL for the LocalStack S3 service.
localstack_endpoint_url() {
  local namespace="${NAMESPACE:-pure-agent}"
  echo "http://localstack.${namespace}.svc.cluster.local:4566"
}

# ── create_s3_test_bucket ────────────────────────────────────────────────────
# Creates the test S3 bucket in LocalStack using kubectl exec on the LocalStack pod.
create_s3_test_bucket() {
  local namespace="${NAMESPACE:-pure-agent}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-integration}"

  _ls_log "Creating S3 test bucket: $S3_TEST_BUCKET"

  kubectl exec deployment/localstack \
    -n "$namespace" \
    --context "$kube_context" \
    -- awslocal s3 mb "s3://$S3_TEST_BUCKET" >&2 2>&1 \
    || _ls_warn "Bucket creation may have failed (bucket might already exist)"

  _ls_log "S3 test bucket ready: $S3_TEST_BUCKET"
}

# ── teardown_localstack ──────────────────────────────────────────────────────
# Removes LocalStack Deployment + Service from the namespace.
teardown_localstack() {
  local namespace="${NAMESPACE:-pure-agent}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-integration}"

  _ls_log "Tearing down LocalStack resources"

  kubectl delete deployment localstack \
    -n "$namespace" --context "$kube_context" --ignore-not-found >&2 || true
  kubectl delete service localstack \
    -n "$namespace" --context "$kube_context" --ignore-not-found >&2 || true

  _ls_log "LocalStack teardown complete"
}

# ── list_s3_objects ──────────────────────────────────────────────────────────
# Lists all objects in the test S3 bucket (for debugging).
# Output: one S3 key per line.
list_s3_objects() {
  local namespace="${NAMESPACE:-pure-agent}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-integration}"

  kubectl exec deployment/localstack \
    -n "$namespace" \
    --context "$kube_context" \
    -- awslocal s3api list-objects \
      --bucket "$S3_TEST_BUCKET" \
      --query 'Contents[].Key' \
      --output text \
    2>/dev/null \
    || echo ""
}

# ── assert_s3_object_exists ──────────────────────────────────────────────────
# Asserts that a specific key exists in the test S3 bucket.
#
# Arguments:
#   $1  key  — S3 object key to check (e.g., "mock-session-123.jsonl")
assert_s3_object_exists() {
  local key="$1"
  local namespace="${NAMESPACE:-pure-agent}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-integration}"

  _ls_log "Checking S3 object exists: s3://$S3_TEST_BUCKET/$key"

  kubectl exec deployment/localstack \
    -n "$namespace" \
    --context "$kube_context" \
    -- awslocal s3api head-object \
      --bucket "$S3_TEST_BUCKET" \
      --key "$key" \
    2>/dev/null \
    || { _ls_fail "assert_s3_object_exists: key '$key' not found in s3://$S3_TEST_BUCKET/"; return 1; }

  _ls_log "PASS assert_s3_object_exists: $key"
}

# ── assert_s3_transcript_exists ──────────────────────────────────────────────
# Asserts that at least min_count transcript (.jsonl) files exist in the S3 bucket.
# Arguments:
#   $1  min_count  — minimum number of transcripts expected (default: 2, planner + agent)
assert_s3_transcript_exists() {
  local min_count="${1:-2}"
  local namespace="${NAMESPACE:-pure-agent}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-integration}"

  _ls_log "Checking for at least $min_count transcript(s) in S3"

  local objects
  objects=$(kubectl exec deployment/localstack \
    -n "$namespace" \
    --context "$kube_context" \
    -- awslocal s3api list-objects \
      --bucket "$S3_TEST_BUCKET" \
      --query 'Contents[].Key' \
      --output text \
    2>/dev/null) \
    || objects=""

  if [[ -z "$objects" || "$objects" == "None" ]]; then
    _ls_fail "assert_s3_transcript_exists: no objects found in s3://$S3_TEST_BUCKET/"
    return 1
  fi

  local transcripts
  transcripts=$(echo "$objects" | tr '\t' '\n' | grep '\.jsonl$' || true)

  if [[ -z "$transcripts" ]]; then
    _ls_log "DEBUG: all objects in bucket: $objects"
    _ls_fail "assert_s3_transcript_exists: no transcript (.jsonl) found in S3"
    return 1
  fi

  local count
  count=$(echo "$transcripts" | wc -l)

  if [[ "$count" -lt "$min_count" ]]; then
    _ls_log "DEBUG: found transcripts: $transcripts"
    _ls_fail "assert_s3_transcript_exists: expected at least $min_count transcript(s), found $count"
    return 1
  fi

  _ls_log "PASS assert_s3_transcript_exists: $count transcript(s) found (min=$min_count)"
}
