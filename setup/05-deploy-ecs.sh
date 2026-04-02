#!/bin/bash
set -e

REGION="us-east-1"
ACCOUNT_ID="036475471569"
CLUSTER="observability-stack"
SUBNET_ID="subnet-02c46382a3cc4dee6"
SECURITY_GROUP_ID="sg-00ea474ff8684449d"

echo "Replacing placeholders in task definitions..."

for FILE in ./ecs/task-definitions/*.json; do
  sed -i "s/036475471569/${ACCOUNT_ID}/g" "${FILE}"
done

echo "Registering ECS task definitions..."

register() {
  local NAME=$1
  local FILE="./ecs/task-definitions/${NAME}.json"
  aws ecs register-task-definition \
    --cli-input-json "file://${FILE}" \
    --region "${REGION}" \
    --query "taskDefinition.taskDefinitionArn" \
    --output text
  echo "Registered: ${NAME}"
}

register "node-exporter"
register "loki"
register "tempo"
register "prometheus"
register "thanos-query"
register "alloy"
register "grafana"

echo ""
echo "Creating ECS services..."

create_service() {
  local NAME=$1
  local TASK_FAMILY=$2
  local DESIRED_COUNT=$3

  aws ecs create-service \
    --cluster "${CLUSTER}" \
    --service-name "observability-${NAME}" \
    --task-definition "${TASK_FAMILY}" \
    --desired-count "${DESIRED_COUNT}" \
    --launch-type EC2 \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ID}],securityGroups=[${SECURITY_GROUP_ID}]}" \
    --region "${REGION}" \
    --scheduling-strategy REPLICA 2>/dev/null \
    && echo "Created service: observability-${NAME}" \
    || echo "Service already exists: observability-${NAME}"
}

create_service "node-exporter"  "observability-node-exporter"  1
create_service "loki"           "observability-loki"            2
create_service "tempo"          "observability-tempo"           1
create_service "prometheus"     "observability-prometheus"      1
create_service "thanos-query"   "observability-thanos-query"    1
create_service "alloy"          "observability-alloy"           2
create_service "grafana"        "observability-grafana"         1

echo ""
echo "All services created in cluster: ${CLUSTER}"
