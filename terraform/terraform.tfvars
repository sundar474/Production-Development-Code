aws_region        = "us-east-1"
account_id        = "036475471569"
cluster_name      = "observability-cluster"
instance_type     = "t3.xlarge"
key_name          = "Sping-key"
security_group_id = "sg-00ea474ff8684449d"
s3_bucket         = "observability-uat-036475471569"
efs_filesystem_id = "fs-0472d91d201b45e43"
ecr_base          = "036475471569.dkr.ecr.us-east-1.amazonaws.com/observability"

# TODO: Replace these two before running terraform apply
vpc_id    = "vpc-001b8e6644bd19236"
subnet_id = "subnet-034cbdba8e226f08b"