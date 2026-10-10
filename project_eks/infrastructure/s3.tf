# S3 Buckets Configuration

# KMS Key for S3 Encryption
resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-s3-kms"
    }
  )
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.project_name}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

# S3 Bucket for File Uploads
resource "aws_s3_bucket" "uploads" {
  bucket = "${var.project_name}-uploads-${var.environment}"

  tags = merge(
    local.tags,
    {
      Name    = "${var.project_name}-uploads"
      Purpose = "File uploads for scanning"
    }
  )
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "delete-old-uploads"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_days
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"] # Restrict this in production
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# S3 Bucket for Quarantine Files
resource "aws_s3_bucket" "quarantine" {
  bucket = "${var.project_name}-quarantine-${var.environment}"

  tags = merge(
    local.tags,
    {
      Name    = "${var.project_name}-quarantine"
      Purpose = "Quarantine for malicious files"
    }
  )
}

resource "aws_s3_bucket_versioning" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    id     = "archive-quarantine"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 1095 # 3 years
    }
  }
}

# Object Lock for Quarantine (prevent deletion)
resource "aws_s3_bucket_object_lock_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 30
    }
  }
}

# S3 Bucket for Reports
resource "aws_s3_bucket" "reports" {
  bucket = "${var.project_name}-reports-${var.environment}"

  tags = merge(
    local.tags,
    {
      Name    = "${var.project_name}-reports"
      Purpose = "Security scan reports"
    }
  )
}

resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id

  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "intelligent-tiering"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "INTELLIGENT_TIERING"
    }

    expiration {
      days = 730 # 2 years
    }
  }
}

# S3 Bucket for CloudFront Logs
resource "aws_s3_bucket" "cloudfront_logs" {
  bucket = "${var.project_name}-cloudfront-logs-${var.environment}"

  tags = merge(
    local.tags,
    {
      Name    = "${var.project_name}-cloudfront-logs"
      Purpose = "CloudFront access logs"
    }
  )
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

# Outputs
output "s3_uploads_bucket_arn" {
  description = "ARN of S3 uploads bucket"
  value       = aws_s3_bucket.uploads.arn
}

output "s3_quarantine_bucket_arn" {
  description = "ARN of S3 quarantine bucket"
  value       = aws_s3_bucket.quarantine.arn
}

output "s3_reports_bucket_arn" {
  description = "ARN of S3 reports bucket"
  value       = aws_s3_bucket.reports.arn
}

output "s3_kms_key_id" {
  description = "KMS key ID for S3 encryption"
  value       = aws_kms_key.s3.key_id
}
