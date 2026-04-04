# Observability Stack — ECS EC2 Deployment Guide

## Architecture Overview

```
Other Team Services (Java / Node.js / Python / Go)
    │  OTel agents · OTLP gRPC/HTTP
    ▼
Internal NLB  (:4317 gRPC · :4318 HTTP)
    │
    ▼
OTel Collector Gateway  ──── tail sampling · PII filtering · enrichment
    │
    ├──── logs   ──────────────────────────► Loki write (2 tasks · t3.xlarge)
    │                                              │ S3: loki/ 90d
    │                                        Loki read (2 tasks · t3.large)
    │
    ├──── traces ─────────────────────────► Tempo (t3.large · S3: tempo/ 14d)
    │
    └──── metrics ─────────────────────────► Grafana Alloy (AZ-A · AZ-B · t3.large)
                                                    │ remote_write
                                                    ▼
                                             Prometheus + Thanos sidecar
                                                    │ ships blocks
                                                    ▼
                                              S3: thanos/ 1yr
                                                    │
                                             Thanos Compactor (scheduled · 2h)
                                             Thanos Query (long-term metrics)

Node Exporter (DAEMON · one per EC2 · :9100) ──► Alloy scrape ──► Prometheus

Grafana (EFS mount · dashboards)
  └── queries: Loki read · Tempo · Thanos Query
```

---

## Prerequisites

| Tool | Minimum Version |
|------|----------------|
| Terraform | >= 1.5.0 |
| AWS CLI | >= 2.x |
| Docker | >= 24.x (with BuildKit) |
| AWS credentials | IAM role or access keys with EC2, ECS, S3, EFS, ECR, IAM, CloudWatch, EventBridge permissions |

---

## Step-by-Step Deployment

### Step 1 — Configure AWS credentials

```bash
aws configure
# or
export AWS_PROFILE=your-profile
```

Verify:
```bash
aws sts get-caller-identity
```

### Step 2 — Clone / enter the project directory

```bash
cd observability/
```

### Step 3 — Terraform init and create ECR repositories first

ECR repos must exist before you can push images.

```bash
terraform init

# Create only ECR repos first (images need to be pushed before full apply)
terraform apply -target=module.ecr
```

### Step 4 — Build and push all Docker images to ECR

```bash
chmod +x scripts/build-and-push.sh
./scripts/build-and-push.sh
```

This will:
- Build all 8 images for `linux/amd64`
- Push them to your ECR repos

Verify images are in ECR:
```bash
aws ecr list-images --repository-name obs-prod-grafana --region ap-south-1
```

### Step 5 — Full Terraform apply

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

This creates in order:
1. S3 bucket (with lifecycle policies)
2. EFS (for Grafana)
3. IAM roles
4. Security groups
5. Internal NLB + all target groups + listeners
6. ECS cluster (EC2 capacity provider)
7. Auto Scaling Group (EC2 instances)
8. All ECS task definitions + services
9. Node Exporter daemon service
10. EventBridge rule for Thanos Compactor (every 2 hours)

Expected apply time: ~8–12 minutes

### Step 6 — Verify services are running

```bash
# Check ECS cluster
aws ecs list-services \
  --cluster obs-prod-observability \
  --region ap-south-1

# Check individual service
aws ecs describe-services \
  --cluster obs-prod-observability \
  --services obs-prod-grafana \
  --region ap-south-1 \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'
```

### Step 7 — Get Grafana URL

Since Grafana runs behind the internal NLB on port 3000:

```bash
terraform output nlb_dns_name
```

Access Grafana at: `http://<nlb-dns>:3000`

> **Note:** The NLB is internal — access it from within the VPC (via VPN, bastion host, or AWS Systems Manager Session Manager).

Default credentials:
- Username: `admin`
- Password: set via `GF_SECURITY_ADMIN_PASSWORD` environment variable (update in `main.tf` → grafana module's environment_vars)

---

## Environment Variables Reference

Set these as ECS task env vars or in AWS Secrets Manager:

| Variable | Used By | Description |
|----------|---------|-------------|
| `S3_BUCKET_NAME` | Loki, Tempo, Thanos | S3 bucket name (auto-set by Terraform) |
| `S3_REGION` | Loki, Tempo, Thanos | `ap-south-1` |
| `LOKI_TARGET` | Loki | `write` or `read` |
| `THANOS_TARGET` | Thanos | `query` or `compactor` |
| `PROMETHEUS_ENDPOINT` | Thanos Query | Prometheus gRPC endpoint |
| `GF_SECURITY_ADMIN_PASSWORD` | Grafana | Admin password |
| `GF_SECURITY_SECRET_KEY` | Grafana | Secret key for sessions |
| `LOKI_WRITE_ENDPOINT` | Alloy | Loki write HTTP endpoint |
| `TEMPO_ENDPOINT` | Alloy, OTel Collector | Tempo OTLP gRPC endpoint |
| `PROM_REMOTE_WRITE` | Alloy | Prometheus remote_write URL |
| `ENVIRONMENT` | OTel Collector, Tempo | `prod` / `staging` / `dev` |

---

## Ports Reference

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| NLB | 4317 | TCP/gRPC | OTLP gRPC ingestion |
| NLB | 4318 | TCP/HTTP | OTLP HTTP ingestion |
| OTel Collector | 4317 | gRPC | OTLP gRPC receive |
| OTel Collector | 4318 | HTTP | OTLP HTTP receive |
| OTel Collector | 13133 | HTTP | Health check |
| OTel Collector | 8888 | HTTP | Self-metrics |
| Grafana Alloy | 4317 | gRPC | OTLP receive from OTel GW |
| Grafana Alloy | 12345 | HTTP | UI + self-metrics |
| Loki write/read | 3100 | HTTP | Push/query logs |
| Loki write/read | 7946 | TCP | Memberlist gossip |
| Tempo | 3200 | HTTP | Trace query |
| Tempo | 4317 | gRPC | OTLP trace receive |
| Prometheus | 9090 | HTTP | Metrics query + remote_write |
| Thanos sidecar | 10901 | gRPC | Block store API |
| Thanos sidecar | 10902 | HTTP | Health/metrics |
| Thanos Query | 9091 | HTTP | Long-term metrics query |
| Grafana | 3000 | HTTP | Dashboard UI |
| Node Exporter | 9100 | HTTP | Host metrics |

---

## Customizing Instance Sizes

Edit `terraform.tfvars`:

```hcl
ec2_instance_type    = "t3.2xlarge"   # change to m5.xlarge for prod
asg_min_size         = 2
asg_max_size         = 6
asg_desired_capacity = 3
```

Service CPU/memory is set per-module in `main.tf`. Example to scale Loki write:
```hcl
module "loki_write" {
  cpu    = 4096    # 4 vCPU
  memory = 16384   # 16 GB
  ...
}
```

---

## Updating a Service

After making config changes, rebuild and push the image, then force a new deployment:

```bash
# Rebuild and push
./scripts/build-and-push.sh

# Force new ECS deployment
aws ecs update-service \
  --cluster obs-prod-observability \
  --service obs-prod-grafana \
  --force-new-deployment \
  --region ap-south-1
```

---

## Useful Debugging Commands

```bash
# View logs for any service in CloudWatch
aws logs tail /ecs/obs-prod/grafana --follow --region ap-south-1
aws logs tail /ecs/obs-prod/loki-write --follow --region ap-south-1
aws logs tail /ecs/obs-prod/otel-collector --follow --region ap-south-1

# List running tasks
aws ecs list-tasks \
  --cluster obs-prod-observability \
  --service-name obs-prod-loki-write \
  --region ap-south-1

# Exec into a running container (requires ECS Exec enabled)
aws ecs execute-command \
  --cluster obs-prod-observability \
  --task <task-id> \
  --container loki-write \
  --interactive \
  --command "/bin/sh"

# Check NLB target health
aws elbv2 describe-target-health \
  --target-group-arn <tg-arn> \
  --region ap-south-1

# Manually trigger Thanos Compactor
aws events put-targets \
  --rule obs-prod-thanos-compactor \
  --targets Id=manual,Arn=<ecs-cluster-arn> \
  --region ap-south-1
```

---

## Teardown

```bash
terraform destroy
```

> ⚠️ This will delete the S3 bucket contents too if `force_destroy = true`. Default is `false` — you must empty the bucket manually first.

---

## File Structure

```
observability/
├── main.tf                          # Root: cluster, services, scheduled tasks
├── variables.tf
├── outputs.tf
├── terraform.tfvars                 # ← Edit your values here
├── modules/
│   ├── s3/main.tf                   # S3 bucket + lifecycle policies
│   ├── efs/main.tf                  # EFS for Grafana
│   ├── iam/main.tf                  # All IAM roles
│   ├── ecr/main.tf                  # ECR repos for all 8 services
│   ├── nlb/main.tf                  # Internal NLB + all listeners
│   ├── security-groups/main.tf      # Per-service security groups
│   └── ecs-service/main.tf          # Reusable ECS service module
├── configs/
│   ├── otel-collector/
│   │   ├── Dockerfile
│   │   └── otelcol-gateway.yaml     # OTel Collector config
│   ├── alloy/
│   │   ├── Dockerfile
│   │   └── alloy.river              # Grafana Alloy config
│   ├── loki/
│   │   ├── Dockerfile
│   │   └── loki.yaml
│   ├── tempo/
│   │   ├── Dockerfile
│   │   └── tempo.yaml
│   ├── prometheus/
│   │   ├── Dockerfile               # Runs Prometheus + Thanos sidecar via supervisord
│   │   ├── prometheus.yaml
│   │   ├── supervisord.conf
│   │   └── thanos-sidecar.yaml
│   ├── thanos/
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh            # Switches between query/compactor via THANOS_TARGET
│   │   └── objstore.yaml
│   ├── grafana/
│   │   ├── Dockerfile
│   │   ├── grafana.ini
│   │   └── provisioning/
│   │       ├── datasources/datasources.yaml   # Loki, Tempo, Thanos auto-wired
│   │       └── dashboards/dashboards.yaml
│   └── node-exporter/
│       └── Dockerfile
└── scripts/
    └── build-and-push.sh            # Build all images and push to ECR
```
