#!/bin/bash
set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
BUCKET="observability-uat-${ACCOUNT_ID}"

echo "Creating S3 bucket: ${BUCKET}"

aws s3api create-bucket \
  --bucket "${BUCKET}" \
  --region "${REGION}"

aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-lifecycle-configuration \
  --bucket "${BUCKET}" \
  --lifecycle-configuration '{
    "Rules": [
      {
        "ID": "loki-retention",
        "Status": "Enabled",
        "Filter": {"Prefix": "loki/"},
        "Transitions": [
          {"Days": 30, "StorageClass": "STANDARD_IA"},
          {"Days": 60, "StorageClass": "GLACIER"}
        ],
        "Expiration": {"Days": 90}
      },
      {
        "ID": "tempo-retention",
        "Status": "Enabled",
        "Filter": {"Prefix": "tempo/"},
        "Expiration": {"Days": 14}
      },
      {
        "ID": "thanos-retention",
        "Status": "Enabled",
        "Filter": {"Prefix": "thanos/"},
        "Transitions": [
          {"Days": 15, "StorageClass": "STANDARD_IA"}
        ],
        "Expiration": {"Days": 365}
      }
    ]
  }'

echo ""
echo "S3 bucket created: ${BUCKET}"
echo "Export this for use in other scripts:"
echo "export OBSERVABILITY_BUCKET=${BUCKET}"
