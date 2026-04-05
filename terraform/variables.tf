variable "aws_region" {
  default = "us-east-1"
}

variable "account_id" {
  default = "036475471569"
}

variable "cluster_name" {
  default = "observability-cluster"
}

variable "instance_type" {
  default = "t3.xlarge"
}

variable "key_name" {
  default = "Sping-key"
}

variable "security_group_id" {
  default = "sg-00ea474ff8684449d"
}

variable "s3_bucket" {
  default = "observability-uat-036475471569"
}

variable "efs_filesystem_id" {
  default = "fs-0472d91d201b45e43"
}

variable "ecr_base" {
  default = "036475471569.dkr.ecr.us-east-1.amazonaws.com/observability"
}

# Subnet to place the ECS EC2 instance and awsvpc tasks in
variable "subnet_id" {
  description = "Subnet ID for the ECS EC2 instance and awsvpc tasks"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID that contains the subnet"
  type        = string
}
