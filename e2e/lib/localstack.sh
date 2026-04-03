#!/usr/bin/env bash
# e2e/lib/localstack.sh — LocalStack S3 배포 및 transcript 검증 헬퍼
#
# Functions:
#   deploy_localstack <bucket_name> <namespace> <kube_context>
#   assert_s3_transcripts_exist <bucket_name> <namespace> <kube_context>

set -euo pipefail

if [[ "${1:-}" == "--source-only" ]]; then
  true
fi

# ── Logging ───────────────────────────────────────────────────────────────────
_ls_log()  { echo "[localstack] $*" >&2; }
_ls_fail() { echo "FAIL $*" >&2; return 1; }

# ── deploy_localstack ────────────────────────────────────────────────────────
# LocalStack을 Kubernetes Deployment + Service로 배포하고 S3 버킷을 생성합니다.
#
# Arguments:
#   $1  bucket_name  — 생성할 S3 버킷 이름
#   $2  namespace    — kubernetes namespace
#   $3  kube_context — kubectl context
#
deploy_localstack() {
  local bucket_name="$1"
  local namespace="$2"
  local kube_context="$3"

  _ls_log "Deploying LocalStack (bucket=$bucket_name, ns=$namespace)"

  cat <<EOF | kubectl --context "$kube_context" apply -n "$namespace" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: localstack
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
          image: localstack/localstack:3
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 4566
          env:
            - name: SERVICES
              value: "s3"
          readinessProbe:
            httpGet:
              path: /_localstack/health
              port: 4566
            initialDelaySeconds: 5
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: localstack
spec:
  selector:
    app: localstack
  ports:
    - port: 4566
      targetPort: 4566
EOF

  _ls_log "Waiting for LocalStack rollout..."
  kubectl --context "$kube_context" -n "$namespace" \
    rollout status deployment/localstack --timeout=120s

  # 버킷 생성 (awslocal은 LocalStack 컨테이너에 내장)
  _ls_log "Creating S3 bucket: $bucket_name"
  local retries=0
  while ! kubectl --context "$kube_context" -n "$namespace" \
    exec deploy/localstack -- awslocal s3 mb "s3://${bucket_name}" 2>/dev/null; do
    retries=$((retries + 1))
    if [[ "$retries" -ge 10 ]]; then
      _ls_fail "deploy_localstack: failed to create bucket $bucket_name after $retries retries"
      return 1
    fi
    _ls_log "Waiting for LocalStack S3 to be ready (retry $retries/10)..."
    sleep 3
  done

  _ls_log "LocalStack deployed, bucket $bucket_name created"
}

# ── assert_s3_transcripts_exist ──────────────────────────────────────────────
# S3 버킷에 transcript .jsonl 파일이 업로드되었는지 검증합니다.
#
# Arguments:
#   $1  bucket_name  — S3 버킷 이름
#   $2  namespace    — kubernetes namespace
#   $3  kube_context — kubectl context
#
assert_s3_transcripts_exist() {
  local bucket_name="$1"
  local namespace="$2"
  local kube_context="$3"

  _ls_log "Checking S3 transcripts in bucket: $bucket_name"

  local listing
  listing=$(kubectl --context "$kube_context" -n "$namespace" \
    exec deploy/localstack -- awslocal s3 ls "s3://${bucket_name}/" --recursive 2>/dev/null) \
    || { _ls_fail "assert_s3_transcripts_exist: failed to list S3 bucket $bucket_name"; return 1; }

  local jsonl_count
  jsonl_count=$(echo "$listing" | grep -c '\.jsonl$' || true)

  if [[ "$jsonl_count" -eq 0 ]]; then
    _ls_log "S3 bucket contents:"
    echo "$listing" >&2
    _ls_fail "assert_s3_transcripts_exist: no .jsonl files found in s3://$bucket_name/"
    return 1
  fi

  _ls_log "PASS assert_s3_transcripts_exist: $jsonl_count .jsonl file(s) in s3://$bucket_name/"
}
