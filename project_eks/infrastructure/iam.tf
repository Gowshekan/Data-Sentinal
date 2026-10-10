# IAM Roles and Policies

# IAM Role for EKS Pod Execution (IRSA)
resource "aws_iam_role" "eks_pod_execution" {
  name = "${var.project_name}-eks-pod-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:virusprotect:app-service-account"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.tags
}

# IAM Policy for S3 Access
resource "aws_iam_policy" "s3_access" {
  name        = "${var.project_name}-s3-access"
  description = "Policy for accessing S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.uploads.arn,
          "${aws_s3_bucket.uploads.arn}/*",
          aws_s3_bucket.quarantine.arn,
          "${aws_s3_bucket.quarantine.arn}/*",
          aws_s3_bucket.reports.arn,
          "${aws_s3_bucket.reports.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [aws_kms_key.s3.arn]
      }
    ]
  })

  tags = local.tags
}

# IAM Policy for SQS Access
resource "aws_iam_policy" "sqs_access" {
  name        = "${var.project_name}-sqs-access"
  description = "Policy for accessing SQS queues"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [
          aws_sqs_queue.scan_queue.arn,
          aws_sqs_queue.scan_queue_dlq.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [aws_kms_key.sqs.arn]
      }
    ]
  })

  tags = local.tags
}

# IAM Policy for SNS Access
resource "aws_iam_policy" "sns_access" {
  name        = "${var.project_name}-sns-access"
  description = "Policy for publishing to SNS topics"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.scan_alerts.arn,
          aws_sns_topic.critical_threats.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [aws_kms_key.sns.arn]
      }
    ]
  })

  tags = local.tags
}

# IAM Policy for Secrets Manager Access
resource "aws_iam_policy" "secrets_manager_access" {
  name        = "${var.project_name}-secrets-manager-access"
  description = "Policy for accessing Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.rds_credentials.arn,
          aws_secretsmanager_secret.opensearch_credentials.arn,
          aws_secretsmanager_secret.virustotal_api_key.arn
        ]
      }
    ]
  })

  tags = local.tags
}

# IAM Policy for CloudWatch Logs
resource "aws_iam_policy" "cloudwatch_logs_access" {
  name        = "${var.project_name}-cloudwatch-logs-access"
  description = "Policy for writing CloudWatch logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${local.cluster_name}/*"
      }
    ]
  })

  tags = local.tags
}

# IAM Policy for X-Ray
resource "aws_iam_policy" "xray_access" {
  name        = "${var.project_name}-xray-access"
  description = "Policy for AWS X-Ray tracing"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

# Attach policies to pod execution role
resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.eks_pod_execution.name
  policy_arn = aws_iam_policy.s3_access.arn
}

resource "aws_iam_role_policy_attachment" "sqs_access" {
  role       = aws_iam_role.eks_pod_execution.name
  policy_arn = aws_iam_policy.sqs_access.arn
}

resource "aws_iam_role_policy_attachment" "sns_access" {
  role       = aws_iam_role.eks_pod_execution.name
  policy_arn = aws_iam_policy.sns_access.arn
}

resource "aws_iam_role_policy_attachment" "secrets_manager_access" {
  role       = aws_iam_role.eks_pod_execution.name
  policy_arn = aws_iam_policy.secrets_manager_access.arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs_access" {
  role       = aws_iam_role.eks_pod_execution.name
  policy_arn = aws_iam_policy.cloudwatch_logs_access.arn
}

resource "aws_iam_role_policy_attachment" "xray_access" {
  role       = aws_iam_role.eks_pod_execution.name
  policy_arn = aws_iam_policy.xray_access.arn
}

# Store VirusTotal API Key in Secrets Manager
resource "aws_secretsmanager_secret" "virustotal_api_key" {
  name                    = "${var.project_name}/virustotal/api-key"
  recovery_window_in_days = 7

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "virustotal_api_key" {
  secret_id = aws_secretsmanager_secret.virustotal_api_key.id

  secret_string = jsonencode({
    apiKey = var.vt_api_key
  })
}

# Outputs
output "eks_pod_execution_role_arn" {
  description = "ARN of EKS pod execution role"
  value       = aws_iam_role.eks_pod_execution.arn
}

output "virustotal_secret_arn" {
  description = "ARN of VirusTotal API key secret"
  value       = aws_secretsmanager_secret.virustotal_api_key.arn
}
