#!/usr/bin/env bash
# e2e/lib/localstack.sh — LocalStack S3 deployment and assertion helpers
#
# Deploys LocalStack as a Kubernetes Deployment + Service in the test namespace
# for S3 transcript upload verification in Level 2 and Level 3 E2E tests.
#
# Functions:
#   deploy_localstack       — Create LocalStack Deployment + Service
#   wait_localstack         — Wait for LocalStack to be ready
#   create_s3_test_bucket   — Create the test S3 bucket
#   teardown_localstack     — Remove LocalStack resources
#   localstack_endpoint_url — Return the in-cluster LocalStack S3 endpoint URL
#   list_s3_objects         — List objects in the test bucket (debug helper)
#   assert_s3_object_exists — Assert a specific S3 key exists
#   assert_s3_transcript_exists     — Assert agent transcript files exist in S3
#   assert_s3_planner_transcript_exists — Assert planner transcript files exist in S3
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
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"

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
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"

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
# Creates the test S3 bucket in LocalStack using a temporary pod.
create_s3_test_bucket() {
  local namespace="${NAMESPACE:-pure-agent}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"
  local endpoint_url
  endpoint_url=$(localstack_endpoint_url)

  _ls_log "Creating S3 test bucket: $S3_TEST_BUCKET (endpoint=$endpoint_url)"

  kubectl run localstack-setup-$$ \
    --image=amazon/aws-cli:2.27.28 \
    --restart=Never \
    --rm \
    --attach \
    -n "$namespace" \
    --context "$kube_context" \
    --env="AWS_ACCESS_KEY_ID=test" \
    --env="AWS_SECRET_ACCESS_KEY=test" \
    --env="AWS_DEFAULT_REGION=ap-northeast-2" \
    --command -- \
    aws --endpoint-url "$endpoint_url" s3 mb "s3://$S3_TEST_BUCKET" >&2 2>&1 \
    || _ls_warn "Bucket creation may have failed (bucket might already exist)"

  _ls_log "S3 test bucket ready: $S3_TEST_BUCKET"
}

# ── teardown_localstack ──────────────────────────────────────────────────────
# Removes LocalStack Deployment + Service from the namespace.
teardown_localstack() {
  local namespace="${NAMESPACE:-pure-agent}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"

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
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"
  local endpoint_url
  endpoint_url=$(localstack_endpoint_url)

  kubectl run localstack-list-$$ \
    --image=amazon/aws-cli:2.27.28 \
    --restart=Never \
    --rm \
    --attach \
    -n "$namespace" \
    --context "$kube_context" \
    --env="AWS_ACCESS_KEY_ID=test" \
    --env="AWS_SECRET_ACCESS_KEY=test" \
    --env="AWS_DEFAULT_REGION=ap-northeast-2" \
    --command -- \
    aws --endpoint-url "$endpoint_url" s3api list-objects \
      --bucket "$S3_TEST_BUCKET" \
      --query 'Contents[].Key' \
      --output text \
    2>/dev/null | grep -v '^pod .* deleted' \
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
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"
  local endpoint_url
  endpoint_url=$(localstack_endpoint_url)

  _ls_log "Checking S3 object exists: s3://$S3_TEST_BUCKET/$key"

  kubectl run localstack-check-$$ \
    --image=amazon/aws-cli:2.27.28 \
    --restart=Never \
    --rm \
    --attach \
    -n "$namespace" \
    --context "$kube_context" \
    --env="AWS_ACCESS_KEY_ID=test" \
    --env="AWS_SECRET_ACCESS_KEY=test" \
    --env="AWS_DEFAULT_REGION=ap-northeast-2" \
    --command -- \
    aws --endpoint-url "$endpoint_url" s3api head-object \
      --bucket "$S3_TEST_BUCKET" \
      --key "$key" \
    2>/dev/null | grep -v '^pod .* deleted' \
    || { _ls_fail "assert_s3_object_exists: key '$key' not found in s3://$S3_TEST_BUCKET/"; return 1; }

  _ls_log "PASS assert_s3_object_exists: $key"
}

# ── assert_s3_transcript_exists ──────────────────────────────────────────────
# Asserts that at least one agent transcript (.jsonl) exists in the S3 bucket.
# Excludes planner transcripts (files starting with "planner-").
assert_s3_transcript_exists() {
  local namespace="${NAMESPACE:-pure-agent}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"
  local endpoint_url
  endpoint_url=$(localstack_endpoint_url)

  _ls_log "Checking for agent transcript(s) in S3"

  local objects
  objects=$(kubectl run localstack-transcript-check-$$ \
    --image=amazon/aws-cli:2.27.28 \
    --restart=Never \
    --rm \
    --attach \
    -n "$namespace" \
    --context "$kube_context" \
    --env="AWS_ACCESS_KEY_ID=test" \
    --env="AWS_SECRET_ACCESS_KEY=test" \
    --env="AWS_DEFAULT_REGION=ap-northeast-2" \
    --command -- \
    aws --endpoint-url "$endpoint_url" s3api list-objects \
      --bucket "$S3_TEST_BUCKET" \
      --query 'Contents[].Key' \
      --output text \
    2>/dev/null | grep -v '^pod .* deleted') \
    || objects=""

  if [[ -z "$objects" || "$objects" == "None" ]]; then
    _ls_fail "assert_s3_transcript_exists: no objects found in s3://$S3_TEST_BUCKET/"
    return 1
  fi

  # Filter for .jsonl files that are NOT planner transcripts
  local agent_transcripts
  agent_transcripts=$(echo "$objects" | tr '\t' '\n' | grep '\.jsonl$' | grep -v '^planner-' || true)

  if [[ -z "$agent_transcripts" ]]; then
    _ls_log "DEBUG: all objects in bucket: $objects"
    _ls_fail "assert_s3_transcript_exists: no agent transcript (.jsonl) found in S3"
    return 1
  fi

  local count
  count=$(echo "$agent_transcripts" | wc -l)
  _ls_log "PASS assert_s3_transcript_exists: $count agent transcript(s) found"
}

# ── assert_s3_planner_transcript_exists ──────────────────────────────────────
# Asserts that at least one planner transcript (planner-*.jsonl) exists in S3.
assert_s3_planner_transcript_exists() {
  local namespace="${NAMESPACE:-pure-agent}"
  local kube_context="${KUBE_CONTEXT:-kind-pure-agent-e2e-level2}"
  local endpoint_url
  endpoint_url=$(localstack_endpoint_url)

  _ls_log "Checking for planner transcript(s) in S3"

  local objects
  objects=$(kubectl run localstack-planner-check-$$ \
    --image=amazon/aws-cli:2.27.28 \
    --restart=Never \
    --rm \
    --attach \
    -n "$namespace" \
    --context "$kube_context" \
    --env="AWS_ACCESS_KEY_ID=test" \
    --env="AWS_SECRET_ACCESS_KEY=test" \
    --env="AWS_DEFAULT_REGION=ap-northeast-2" \
    --command -- \
    aws --endpoint-url "$endpoint_url" s3api list-objects \
      --bucket "$S3_TEST_BUCKET" \
      --query 'Contents[].Key' \
      --output text \
    2>/dev/null) \
    || objects=""

  if [[ -z "$objects" || "$objects" == "None" ]]; then
    _ls_fail "assert_s3_planner_transcript_exists: no objects found in s3://$S3_TEST_BUCKET/"
    return 1
  fi

  # Filter for planner-*.jsonl files
  local planner_transcripts
  planner_transcripts=$(echo "$objects" | tr '\t' '\n' | grep '^planner-.*\.jsonl$' || true)

  if [[ -z "$planner_transcripts" ]]; then
    _ls_log "DEBUG: all objects in bucket: $objects"
    _ls_fail "assert_s3_planner_transcript_exists: no planner transcript (planner-*.jsonl) found in S3"
    return 1
  fi

  local count
  count=$(echo "$planner_transcripts" | wc -l)
  _ls_log "PASS assert_s3_planner_transcript_exists: $count planner transcript(s) found"
}
