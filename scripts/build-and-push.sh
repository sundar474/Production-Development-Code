#!/bin/bash
# =============================================================================
# build-and-push.sh
# Builds all Docker images and pushes to ECR
# Usage: ./scripts/build-and-push.sh [AWS_ACCOUNT_ID] [REGION] [ENV]
# Example: ./scripts/build-and-push.sh 123456789012 ap-south-1 prod
# =============================================================================

set -euo pipefail

AWS_ACCOUNT_ID="${1:-$(aws sts get-caller-identity --query Account --output text)}"
REGION="${2:-ap-south-1}"
ENV="${3:-prod}"
PROJECT="obs"
ECR_BASE="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "============================================================"
echo "  Building & pushing observability images to ECR"
echo "  Account : ${AWS_ACCOUNT_ID}"
echo "  Region  : ${REGION}"
echo "  Env     : ${ENV}"
echo "  ECR Base: ${ECR_BASE}"
echo "============================================================"

# ECR login
echo "→ Logging into ECR..."
aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${ECR_BASE}"

# Map: service_name → Dockerfile directory
declare -A SERVICES=(
  ["otel-collector"]="configs/otel-collector"
  ["grafana-alloy"]="configs/alloy"
  ["loki"]="configs/loki"
  ["tempo"]="configs/tempo"
  ["prometheus"]="configs/prometheus"
  ["thanos"]="configs/thanos"
  ["grafana"]="configs/grafana"
  ["node-exporter"]="configs/node-exporter"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"

for SERVICE in "${!SERVICES[@]}"; do
  DIR="${ROOT_DIR}/${SERVICES[$SERVICE]}"
  REPO="${ECR_BASE}/${PROJECT}-${ENV}-${SERVICE}"
  TAG="latest"
  FULL_TAG="${REPO}:${TAG}"

  echo ""
  echo "──────────────────────────────────────────────"
  echo "  Building  : ${SERVICE}"
  echo "  Directory : ${DIR}"
  echo "  Image     : ${FULL_TAG}"
  echo "──────────────────────────────────────────────"

  if [ ! -f "${DIR}/Dockerfile" ]; then
    echo "  ⚠ WARNING: No Dockerfile found in ${DIR}, skipping."
    continue
  fi

  docker build \
    --platform linux/amd64 \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    -t "${FULL_TAG}" \
    "${DIR}"

  echo "  → Pushing ${FULL_TAG}..."
  docker push "${FULL_TAG}"
  echo "  ✓ Done: ${SERVICE}"
done

echo ""
echo "============================================================"
echo "  ✅ All images built and pushed successfully!"
echo "  Next: terraform init && terraform apply"
echo "============================================================"
