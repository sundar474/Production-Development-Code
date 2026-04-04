variable "project_name" {}
variable "environment" {}
variable "tags" { type = map(string) }

resource "aws_s3_bucket" "observability" {
  bucket        = "${var.project_name}-${var.environment}-observability-backend"
  force_destroy = false
  tags          = var.tags
}

resource "aws_s3_bucket_versioning" "observability" {
  bucket = aws_s3_bucket.observability.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "observability" {
  bucket = aws_s3_bucket.observability.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "observability" {
  bucket                  = aws_s3_bucket.observability.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policies per architecture: loki/90d · tempo/14d · thanos/1yr
resource "aws_s3_bucket_lifecycle_configuration" "observability" {
  bucket = aws_s3_bucket.observability.id

  rule {
    id     = "loki-retention-90d"
    status = "Enabled"
    filter { prefix = "loki/" }
    expiration { days = 90 }
    noncurrent_version_expiration { noncurrent_days = 7 }
  }

  rule {
    id     = "tempo-retention-14d"
    status = "Enabled"
    filter { prefix = "tempo/" }
    expiration { days = 14 }
    noncurrent_version_expiration { noncurrent_days = 3 }
  }

  rule {
    id     = "thanos-retention-1yr"
    status = "Enabled"
    filter { prefix = "thanos/" }
    expiration { days = 365 }
    noncurrent_version_expiration { noncurrent_days = 30 }
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 180
      storage_class = "GLACIER"
    }
  }
}

output "bucket_id" {
  value = aws_s3_bucket.observability.id
}

output "bucket_arn" {
  value = aws_s3_bucket.observability.arn
}
