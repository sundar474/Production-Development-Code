#!/bin/bash
set -e

REGION="us-east-1"
ACCOUNT_ID="036475471569"
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Logging in to ECR..."
aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${ECR_BASE}"

build_and_push() {
  local NAME=$1
  local CONTEXT=$2
  local TAG="${ECR_BASE}/observability/${NAME}:latest"

  echo ""
  echo "Building: ${NAME}"
  docker build -t "${TAG}" "${CONTEXT}"

  echo "Pushing: ${NAME}"
  docker push "${TAG}"

  echo "Done: ${NAME}"
}

build_and_push "alloy"          "./docker/alloy"
build_and_push "loki"           "./docker/loki"
build_and_push "tempo"          "./docker/tempo"
build_and_push "prometheus"     "./docker/prometheus"
build_and_push "grafana"        "./docker/grafana"
build_and_push "node-exporter"  "./docker/node-exporter"

# Thanos uses upstream image directly - just retag and push
echo ""
echo "Pushing thanos..."
docker pull quay.io/thanos/thanos:v0.35.1
docker tag quay.io/thanos/thanos:v0.35.1 "${ECR_BASE}/observability/thanos:latest"
docker push "${ECR_BASE}/observability/thanos:latest"

echo ""
echo "All images pushed to ECR."
echo "ECR base: ${ECR_BASE}"
