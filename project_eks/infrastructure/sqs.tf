# SQS Queue and SNS Configuration

# SQS Queue for Scan Jobs
resource "aws_sqs_queue" "scan_queue" {
  name                       = "${var.project_name}-scan-queue"
  delay_seconds              = 0
  max_message_size           = 262144 # 256 KB
  message_retention_seconds  = 1209600 # 14 days
  receive_wait_time_seconds  = 20 # Enable long polling
  visibility_timeout_seconds = 300 # 5 minutes

  # Enable encryption
  kms_master_key_id                 = aws_kms_key.sqs.id
  kms_data_key_reuse_period_seconds = 300

  # Dead Letter Queue
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.scan_queue_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-scan-queue"
    }
  )
}

# Dead Letter Queue
resource "aws_sqs_queue" "scan_queue_dlq" {
  name                       = "${var.project_name}-scan-queue-dlq"
  message_retention_seconds  = 1209600 # 14 days
  receive_wait_time_seconds  = 20
  kms_master_key_id          = aws_kms_key.sqs.id
  kms_data_key_reuse_period_seconds = 300

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-scan-queue-dlq"
    }
  )
}

# KMS Key for SQS Encryption
resource "aws_kms_key" "sqs" {
  description             = "KMS key for SQS encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-sqs-kms"
    }
  )
}

resource "aws_kms_alias" "sqs" {
  name          = "alias/${var.project_name}-sqs"
  target_key_id = aws_kms_key.sqs.key_id
}

# SQS Queue Policy (allow EKS pods to access)
resource "aws_sqs_queue_policy" "scan_queue" {
  queue_url = aws_sqs_queue.scan_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.eks_pod_execution.arn
        }
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.scan_queue.arn
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.eks_pod_execution.arn
        }
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.scan_queue.arn
      }
    ]
  })
}

# SNS Topic for Notifications
resource "aws_sns_topic" "scan_alerts" {
  name              = "${var.project_name}-scan-alerts"
  display_name      = "VirusProtect Scan Alerts"
  kms_master_key_id = aws_kms_key.sns.id

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-scan-alerts"
    }
  )
}

# SNS Topic for Critical Threats
resource "aws_sns_topic" "critical_threats" {
  name              = "${var.project_name}-critical-threats"
  display_name      = "VirusProtect Critical Threats"
  kms_master_key_id = aws_kms_key.sns.id

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-critical-threats"
    }
  )
}

# KMS Key for SNS Encryption
resource "aws_kms_key" "sns" {
  description             = "KMS key for SNS encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-sns-kms"
    }
  )
}

resource "aws_kms_alias" "sns" {
  name          = "alias/${var.project_name}-sns"
  target_key_id = aws_kms_key.sns.key_id
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "scan_alerts" {
  arn = aws_sns_topic.scan_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.eks_pod_execution.arn
        }
        Action = [
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.scan_alerts.arn
      }
    ]
  })
}

# CloudWatch Alarm for Queue Depth
resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  alarm_name          = "${var.project_name}-sqs-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "100"
  alarm_description   = "This metric monitors SQS queue depth"
  alarm_actions       = [aws_sns_topic.scan_alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.scan_queue.name
  }

  tags = local.tags
}

# CloudWatch Alarm for Dead Letter Queue
resource "aws_cloudwatch_metric_alarm" "sqs_dlq_messages" {
  alarm_name          = "${var.project_name}-sqs-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Messages in Dead Letter Queue"
  alarm_actions       = [aws_sns_topic.critical_threats.arn]

  dimensions = {
    QueueName = aws_sqs_queue.scan_queue_dlq.name
  }

  tags = local.tags
}

# EventBridge Rule for Scheduled Scans
resource "aws_cloudwatch_event_rule" "scheduled_scans" {
  name                = "${var.project_name}-scheduled-scans"
  description         = "Trigger scheduled security scans"
  schedule_expression = "rate(1 day)"

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "scheduled_scans" {
  rule      = aws_cloudwatch_event_rule.scheduled_scans.name
  target_id = "SendToSQS"
  arn       = aws_sqs_queue.scan_queue.arn

  input = jsonencode({
    type      = "scheduled_scan"
    timestamp = "{{aws.events.rule.execution-time}}"
  })
}

# Allow EventBridge to send to SQS
resource "aws_sqs_queue_policy" "eventbridge_to_sqs" {
  queue_url = aws_sqs_queue.scan_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.scan_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.scheduled_scans.arn
          }
        }
      }
    ]
  })
}

# Outputs
output "sqs_queue_arn" {
  description = "ARN of SQS scan queue"
  value       = aws_sqs_queue.scan_queue.arn
}

output "sqs_dlq_arn" {
  description = "ARN of SQS dead letter queue"
  value       = aws_sqs_queue.scan_queue_dlq.arn
}

output "sns_scan_alerts_arn" {
  description = "ARN of SNS scan alerts topic"
  value       = aws_sns_topic.scan_alerts.arn
}

output "sns_critical_threats_arn" {
  description = "ARN of SNS critical threats topic"
  value       = aws_sns_topic.critical_threats.arn
}
