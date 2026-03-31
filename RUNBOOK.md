# Observability Stack — UAT Deployment Runbook

## Placeholders to replace before running anything

Search for these strings across all files and replace them:

| Placeholder           | What to put                              |
|-----------------------|------------------------------------------|
| <ACCOUNT_ID>          | Your 12-digit AWS account ID             |
| <CLUSTER_NAME>        | Your ECS cluster name                    |
| <YOUR_SUBNET_ID>      | Subnet ID in your VPC for ECS tasks      |
| <YOUR_SECURITY_GROUP_ID> | Security group for observability tasks|
| <EFS_FILESYSTEM_ID>   | EFS filesystem ID for Grafana dashboards |

---

## Step 1 — Create S3 bucket

```bash
chmod +x setup/01-s3-setup.sh
./setup/01-s3-setup.sh
```

This creates the bucket with three prefixes and lifecycle policies:
- loki/   → 90 days (30d standard, 60d IA, then deleted)
- tempo/  → 14 days then deleted
- thanos/ → 1 year (15d standard, then IA, then deleted)

---

## Step 2 — Create IAM roles

```bash
chmod +x setup/02-iam-setup.sh
./setup/02-iam-setup.sh
```

Creates two roles:
- observability-ecs-execution-role — pulls images from ECR, writes logs to CloudWatch
- observability-ecs-task-role     — reads and writes to S3

---

## Step 3 — Create ECR repositories

```bash
chmod +x setup/03-ecr-setup.sh
./setup/03-ecr-setup.sh
```

Creates 7 repositories under the observability/ prefix.

---

## Step 4 — Build and push images

```bash
chmod +x setup/04-build-push.sh
./setup/04-build-push.sh
```

Builds custom images with configs baked in and pushes all 8 to ECR.
Run this from the root of this repository.

---

## Step 5 — Create EFS for Grafana

```bash
# Create EFS filesystem
aws efs create-file-system \
  --region us-east-1 \
  --tags Key=Name,Value=observability-grafana-efs \
  --query "FileSystemId" \
  --output text

# Note the FileSystemId and replace <EFS_FILESYSTEM_ID>
# in ecs/task-definitions/grafana.json
```

---

## Step 6 — Create security group rules

The observability security group needs these inbound rules:

| Port  | Protocol | Source            | Used by             |
|-------|----------|-------------------|---------------------|
| 4317  | TCP      | App cluster SG    | Alloy OTLP gRPC     |
| 4318  | TCP      | App cluster SG    | Alloy OTLP HTTP     |
| 3100  | TCP      | Internal          | Loki                |
| 3200  | TCP      | Internal          | Tempo               |
| 9090  | TCP      | Internal          | Prometheus          |
| 10902 | TCP      | Internal          | Thanos Query        |
| 3000  | TCP      | Your IP / ALB     | Grafana UI          |
| 9100  | TCP      | Internal          | Node Exporter       |
| 12345 | TCP      | Internal          | Alloy UI            |

---

## Step 7 — Deploy to ECS

Edit setup/05-deploy-ecs.sh and set:
- CLUSTER to your ECS cluster name
- SUBNET_ID to your subnet
- SECURITY_GROUP_ID to your security group

```bash
chmod +x setup/05-deploy-ecs.sh
./setup/05-deploy-ecs.sh
```

---

## Step 8 — Verify all services are running

```bash
aws ecs list-services \
  --cluster <CLUSTER_NAME> \
  --query "serviceArns" \
  --output table

# Check each service task count
aws ecs describe-services \
  --cluster <CLUSTER_NAME> \
  --services \
    observability-alloy \
    observability-loki \
    observability-tempo \
    observability-prometheus \
    observability-thanos-query \
    observability-grafana \
    observability-node-exporter \
  --query "services[*].{Name:serviceName,Running:runningCount,Desired:desiredCount}" \
  --output table
```

All services should show Running = Desired.

---

## Step 9 — Verify signals are flowing

```bash
# Loki ready
curl http://<loki-task-ip>:3100/ready

# Tempo ready
curl http://<tempo-task-ip>:3200/ready

# Prometheus targets
curl http://<prometheus-task-ip>:9090/api/v1/targets | python3 -m json.tool | grep health

# Traces received by Tempo
curl http://<tempo-task-ip>:3200/api/search/tag/service.name/values | python3 -m json.tool

# Thanos Query working
curl http://<thanos-query-task-ip>:10902/-/ready
```

---

## Step 10 — Access Grafana

Open in browser: http://<grafana-task-ip>:3000
Login: admin / changeme (change this immediately)

Go to Explore and verify:
1. Prometheus — query node_cpu_seconds_total, should return data
2. Loki — select container label, should show logs
3. Tempo — search traces, should show spans from your services
4. Thanos — query same metrics as Prometheus, both should return data

---

## Local testing first (recommended)

Before deploying to ECS, test locally with Docker Compose:

```bash
docker-compose up -d
docker-compose ps
```

All services should show healthy.
Then open http://localhost:3000 and verify all four datasources work.

---

## File structure

```
observability/
├── docker-compose.yml              # Local test only
├── setup/
│   ├── 01-s3-setup.sh
│   ├── 02-iam-setup.sh
│   ├── 03-ecr-setup.sh
│   ├── 04-build-push.sh
│   └── 05-deploy-ecs.sh
├── docker/
│   ├── alloy/          Dockerfile + config.alloy
│   ├── loki/           Dockerfile + loki-config.yml (S3)
│   ├── tempo/          Dockerfile + tempo.yml (S3)
│   ├── prometheus/     Dockerfile + prometheus.yml
│   ├── thanos/         Dockerfile
│   ├── grafana/        Dockerfile + provisioning/datasources.yml
│   └── node-exporter/  Dockerfile
├── config/
│   ├── loki/           loki-local.yml (filesystem for local)
│   ├── tempo/          tempo-local.yml (filesystem for local)
│   └── thanos/         bucket-local.yml + bucket-s3.yml
└── ecs/
    └── task-definitions/
        ├── alloy.json
        ├── loki.json
        ├── tempo.json
        ├── prometheus.json
        ├── thanos-query.json
        ├── grafana.json
        └── node-exporter.json
```
