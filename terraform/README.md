# Observability Stack — Terraform Deployment

## What this creates

| Resource | Details |
|---|---|
| ECS Cluster | `observability-cluster` (EC2 launch type) |
| EC2 Instance | `t3.xlarge`, ECS-optimised AMI, key=`Sping-key` |
| IAM Roles | Execution role (ECR + CloudWatch) + Task role (S3) |
| CloudWatch Log Groups | 8 groups under `/ecs/observability/*` |
| Service Discovery | Route53 private zone `observability.local` |
| EFS Mount Target | `fs-0472d91d201b45e43` for Grafana persistence |
| ECS Services | 7 services in correct dependency order (see below) |

## Deployment order (enforced by Terraform depends_on)

```
node-exporter          ← host network, independent
     ↓
prometheus             ← awsvpc, depends on node-exporter
  └─ thanos-sidecar    ← same task, starts after prometheus HEALTHY
loki                   ← awsvpc, independent
tempo                  ← awsvpc, independent
     ↓
alloy                  ← awsvpc, depends on prometheus + loki + tempo
thanos-query           ← awsvpc, depends on prometheus
     ↓
grafana                ← awsvpc, depends on alloy + thanos-query + loki + tempo
```

## Before you run

### Step 1 — Fill in your subnet and VPC

Open `terraform.tfvars` and replace:
```
subnet_id = "subnet-XXXXXXXXXXXXXXXXX"
vpc_id    = "vpc-XXXXXXXXXXXXXXXXX"
```

Find them with:
```bash
aws ec2 describe-subnets --region us-east-1 \
  --query 'Subnets[*].{ID:SubnetId,VPC:VpcId,AZ:AvailabilityZone,CIDR:CidrBlock}' \
  --output table
```

### Step 2 — Rebuild and push Docker images (if not already pushed)

The Terraform uses `:latest` tags from your ECR repos. If images are not yet there:
```bash
cd /path/to/observability
ACCOUNT=036475471569
REGION=us-east-1

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com

for SVC in node-exporter prometheus loki tempo alloy grafana thanos; do
  docker build -t observability/$SVC ./docker/$SVC
  docker tag observability/$SVC $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/observability/$SVC:latest
  docker push $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/observability/$SVC:latest
done
```

### Step 3 — Security group rules required

Your SG `sg-00ea474ff8684449d` must allow these inbound ports (within VPC):

| Port | Service |
|------|---------|
| 9100 | node-exporter |
| 9090 | prometheus |
| 3100, 9095 | loki |
| 3200, 4317, 4318 | tempo |
| 4317, 4318, 12345 | alloy |
| 10901, 10902 | thanos-sidecar + thanos-query |
| 3000 | grafana |

Add them (replace VPC CIDR with yours):
```bash
SG=sg-00ea474ff8684449d
CIDR=10.0.0.0/8   # replace with your VPC CIDR

for PORT in 9100 9090 3100 9095 3200 4317 4318 12345 10901 10902 3000; do
  aws ec2 authorize-security-group-ingress \
    --group-id $SG \
    --protocol tcp \
    --port $PORT \
    --cidr $CIDR \
    --region us-east-1 2>/dev/null || echo "Port $PORT already allowed"
done
```

## Deploy

```bash
cd terraform/

terraform init
terraform plan   # review — should show ~35 resources
terraform apply  # type 'yes' when prompted
```

## Verify services are running

```bash
aws ecs describe-services \
  --cluster observability-cluster \
  --services \
    observability-node-exporter \
    observability-prometheus \
    observability-loki \
    observability-tempo \
    observability-alloy \
    observability-thanos-query \
    observability-grafana \
  --query 'services[*].{Name:serviceName,Running:runningCount,Desired:desiredCount,Status:status}' \
  --output table \
  --region us-east-1
```

All rows should show `Running=1, Desired=1, Status=ACTIVE`.

## Find Grafana IP and open it

```bash
# Get the Grafana task private IP
TASK=$(aws ecs list-tasks \
  --cluster observability-cluster \
  --service-name observability-grafana \
  --query 'taskArns[0]' --output text --region us-east-1)

ENI=$(aws ecs describe-tasks \
  --cluster observability-cluster \
  --tasks $TASK \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text --region us-east-1)

IP=$(aws ec2 describe-network-interfaces \
  --network-interface-ids $ENI \
  --query 'NetworkInterfaces[0].PrivateIpAddress' \
  --output text --region us-east-1)

echo "Grafana: http://$IP:3000  (admin / changeme)"
```

## Check logs if a service fails

```bash
# Replace SERVICE with: node-exporter, prometheus, thanos-sidecar,
#                       loki, tempo, alloy, thanos-query, grafana
SERVICE=prometheus

aws logs tail /ecs/observability/$SERVICE \
  --follow \
  --region us-east-1
```

## Destroy everything

```bash
terraform destroy
```

## Common problems and fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Log group doesn't exist | Execution role missing `logs:CreateLogGroup` | Fixed — cloudwatch.tf pre-creates all groups + iam.tf grants the permission |
| Thanos-sidecar crashes on start | Races prometheus startup | Fixed — `dependsOn: HEALTHY` in task definition |
| Alloy can't connect to loki/tempo/prometheus | Docker-compose DNS doesn't work in ECS | Fixed — Cloud Map service discovery creates `*.observability.local` DNS |
| Loki/Tempo crash on restart | No persistent volume mount | Fixed — `/data/loki` and `/data/tempo` host mounts added |
| Task killed before healthy | `startPeriod` too short | Fixed — Loki/Tempo=90s, others=60s |
| Grafana SQLite corruption on EFS | WAL mode disabled | Fixed — `GF_DATABASE_WAL=true` added |
