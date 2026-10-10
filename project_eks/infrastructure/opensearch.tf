# OpenSearch Domain Configuration

# Generate random password for OpenSearch if not provided
resource "random_password" "opensearch_password" {
  length  = 32
  special = true
}

# OpenSearch Domain
resource "aws_opensearch_domain" "main" {
  domain_name    = "${var.project_name}-search"
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type            = var.opensearch_instance_type
    instance_count           = var.opensearch_instance_count
    dedicated_master_enabled = var.opensearch_instance_count >= 3 ? true : false
    dedicated_master_type    = var.opensearch_instance_count >= 3 ? "t3.small.search" : null
    dedicated_master_count   = var.opensearch_instance_count >= 3 ? 3 : null
    zone_awareness_enabled   = var.opensearch_instance_count > 1 ? true : false

    dynamic "zone_awareness_config" {
      for_each = var.opensearch_instance_count > 1 ? [1] : []
      content {
        availability_zone_count = min(var.opensearch_instance_count, 3)
      }
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.opensearch_ebs_volume_size
    volume_type = "gp3"
    throughput  = 125
    iops        = 3000
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.opensearch.arn
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  vpc_options {
    subnet_ids         = slice(aws_subnet.private[*].id, 0, min(var.opensearch_instance_count, 3))
    security_group_ids = [aws_security_group.opensearch.id]
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = var.opensearch_master_user
      master_user_password = var.opensearch_master_password != null ? var.opensearch_master_password : random_password.opensearch_password.result
    }
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.project_name}-search/*"
      }
    ]
  })

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_application.arn
    log_type                 = "ES_APPLICATION_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_index.arn
    log_type                 = "INDEX_SLOW_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_search.arn
    log_type                 = "SEARCH_SLOW_LOGS"
  }

  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
    "override_main_response_version"         = "false"
  }

  auto_tune_options {
    desired_state       = "ENABLED"
    rollback_on_disable = "NO_ROLLBACK"

    maintenance_schedule {
      start_at = "2024-01-01T00:00:00Z"
      duration {
        value = "2"
        unit  = "HOURS"
      }
      cron_expression_for_recurrence = "cron(0 3 ? * SUN *)"
    }
  }

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-opensearch"
    }
  )

  depends_on = [aws_iam_service_linked_role.opensearch]
}

# IAM Service Linked Role for OpenSearch
resource "aws_iam_service_linked_role" "opensearch" {
  aws_service_name = "es.amazonaws.com"
}

# KMS Key for OpenSearch Encryption
resource "aws_kms_key" "opensearch" {
  description             = "KMS key for OpenSearch encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-opensearch-kms"
    }
  )
}

resource "aws_kms_alias" "opensearch" {
  name          = "alias/${var.project_name}-opensearch"
  target_key_id = aws_kms_key.opensearch.key_id
}

# CloudWatch Log Groups for OpenSearch
resource "aws_cloudwatch_log_group" "opensearch_application" {
  name              = "/aws/opensearch/${var.project_name}/application"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "opensearch_index" {
  name              = "/aws/opensearch/${var.project_name}/index-slow"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "opensearch_search" {
  name              = "/aws/opensearch/${var.project_name}/search-slow"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.tags
}

# CloudWatch Log Resource Policy for OpenSearch
resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  policy_name = "${var.project_name}-opensearch-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "es.amazonaws.com"
        }
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Store OpenSearch credentials in Secrets Manager
resource "aws_secretsmanager_secret" "opensearch_credentials" {
  name                    = "${var.project_name}/opensearch/credentials"
  recovery_window_in_days = 7

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "opensearch_credentials" {
  secret_id = aws_secretsmanager_secret.opensearch_credentials.id

  secret_string = jsonencode({
    username          = var.opensearch_master_user
    password          = var.opensearch_master_password != null ? var.opensearch_master_password : random_password.opensearch_password.result
    endpoint          = aws_opensearch_domain.main.endpoint
    dashboard_endpoint = "https://${aws_opensearch_domain.main.endpoint}/_dashboards"
  })
}

# CloudWatch Alarms for OpenSearch
resource "aws_cloudwatch_metric_alarm" "opensearch_cluster_status_red" {
  alarm_name          = "${var.project_name}-opensearch-cluster-status-red"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ClusterStatus.red"
  namespace           = "AWS/ES"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "1"
  alarm_description   = "OpenSearch cluster status is red"

  dimensions = {
    DomainName = aws_opensearch_domain.main.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_free_storage" {
  alarm_name          = "${var.project_name}-opensearch-free-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/ES"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "10000" # 10GB in MB
  alarm_description   = "OpenSearch free storage space is low"

  dimensions = {
    DomainName = aws_opensearch_domain.main.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = local.tags
}

# Outputs
output "opensearch_domain_id" {
  description = "OpenSearch domain ID"
  value       = aws_opensearch_domain.main.domain_id
}

output "opensearch_domain_arn" {
  description = "OpenSearch domain ARN"
  value       = aws_opensearch_domain.main.arn
}

output "opensearch_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing OpenSearch credentials"
  value       = aws_secretsmanager_secret.opensearch_credentials.arn
}
