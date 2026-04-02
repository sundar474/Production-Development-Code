#!/bin/bash
set -e

REGION="us-east-1"
ACCOUNT_ID="036475471569"

REPOS=(
  "observability/alloy"
  "observability/loki"
  "observability/tempo"
  "observability/prometheus"
  "observability/thanos"
  "observability/grafana"
  "observability/node-exporter"
)

echo "Creating ECR repositories..."

for REPO in "${REPOS[@]}"; do
  aws ecr create-repository \
    --repository-name "${REPO}" \
    --region "${REGION}" \
    --image-scanning-configuration scanOnPush=true 2>/dev/null \
    && echo "Created: ${REPO}" \
    || echo "Already exists: ${REPO}"
done

echo ""
echo "ECR base URI: ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
echo "Export this for build-push script:"
echo "export ECR_BASE=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
