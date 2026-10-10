# RDS PostgreSQL Database

# Generate random password if not provided
resource "random_password" "rds_password" {
  length  = 32
  special = true
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-db-subnet-group"
    }
  )
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-db"

  engine         = "postgres"
  engine_version = "15.4"

  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  db_name  = var.rds_database_name
  username = var.rds_username
  password = var.rds_password != null ? var.rds_password : random_password.rds_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Backup configuration
  backup_retention_period   = var.rds_backup_retention_period
  backup_window             = "03:00-04:00"
  maintenance_window        = "mon:04:00-mon:05:00"
  delete_automated_backups  = false
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-db-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Performance Insights
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  performance_insights_enabled    = true
  performance_insights_retention_period = 7

  # High availability
  multi_az = var.environment == "production" ? true : false

  # Auto minor version upgrade
  auto_minor_version_upgrade = true

  # Deletion protection
  deletion_protection = var.environment == "production" ? true : false

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-db"
    }
  )
}

# KMS Key for RDS Encryption
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-rds-kms"
    }
  )
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# Store RDS credentials in Secrets Manager
resource "aws_secretsmanager_secret" "rds_credentials" {
  name                    = "${var.project_name}/rds/credentials"
  recovery_window_in_days = 7

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id

  secret_string = jsonencode({
    username = aws_db_instance.main.username
    password = var.rds_password != null ? var.rds_password : random_password.rds_password.result
    engine   = "postgres"
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
    url      = "postgresql://${aws_db_instance.main.username}:${var.rds_password != null ? var.rds_password : random_password.rds_password.result}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}"
  })
}

# CloudWatch Alarms for RDS
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-rds-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.project_name}-rds-free-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "5000000000" # 5GB in bytes
  alarm_description   = "This metric monitors RDS free storage space"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = local.tags
}

# Outputs
output "rds_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.main.id
}

output "rds_username" {
  description = "RDS master username"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_db_instance.main.db_name
}

output "rds_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing RDS credentials"
  value       = aws_secretsmanager_secret.rds_credentials.arn
}
