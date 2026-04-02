#!/bin/bash
set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
BUCKET="observability-uat-${ACCOUNT_ID}"

echo "Creating IAM roles..."

# Trust policy for ECS tasks
cat > /tmp/ecs-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# S3 access policy for observability components
cat > /tmp/observability-s3-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET}",
        "arn:aws:s3:::${BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Create task execution role
aws iam create-role \
  --role-name observability-ecs-execution-role \
  --assume-role-policy-document file:///tmp/ecs-trust-policy.json 2>/dev/null || echo "Execution role already exists"

aws iam attach-role-policy \
  --role-name observability-ecs-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Create task role with S3 access
aws iam create-role \
  --role-name observability-ecs-task-role \
  --assume-role-policy-document file:///tmp/ecs-trust-policy.json 2>/dev/null || echo "Task role already exists"

aws iam put-role-policy \
  --role-name observability-ecs-task-role \
  --policy-name observability-s3-access \
  --policy-document file:///tmp/observability-s3-policy.json

echo ""
echo "IAM roles created:"
echo "  Execution role: arn:aws:iam::${ACCOUNT_ID}:role/observability-ecs-execution-role"
echo "  Task role:      arn:aws:iam::${ACCOUNT_ID}:role/observability-ecs-task-role"
