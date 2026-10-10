# ElastiCache Redis Configuration

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-redis-subnet-group"
    }
  )
}

# ElastiCache Redis Cluster
resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_nodes      = var.redis_num_cache_nodes
  parameter_group_name = aws_elasticache_parameter_group.main.name
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]

  port                       = 6379
  maintenance_window         = "sun:05:00-sun:06:00"
  snapshot_window            = "03:00-04:00"
  snapshot_retention_limit   = 5
  final_snapshot_identifier  = "${var.project_name}-redis-final-snapshot"
  automatic_failover_enabled = false

  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token_enabled         = false

  # Logging
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_engine_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = merge(
    local.tags,
    {
      Name = "${var.project_name}-redis"
    }
  )
}

# ElastiCache Parameter Group
resource "aws_elasticache_parameter_group" "main" {
  name   = "${var.project_name}-redis-params"
  family = "redis7"

  # Optimize for caching
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  tags = local.tags
}

# CloudWatch Log Groups for Redis
resource "aws_cloudwatch_log_group" "redis_slow_log" {
  name              = "/aws/elasticache/${var.project_name}/redis/slow-log"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "redis_engine_log" {
  name              = "/aws/elasticache/${var.project_name}/redis/engine-log"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.tags
}

# CloudWatch Alarms for Redis
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "${var.project_name}-redis-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "This metric monitors Redis CPU utilization"

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.main.id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name          = "${var.project_name}-redis-memory-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors Redis memory utilization"

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.main.id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "redis_evictions" {
  alarm_name          = "${var.project_name}-redis-evictions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1000"
  alarm_description   = "This metric monitors Redis evictions"

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.main.id
  }

  tags = local.tags
}

# Outputs
output "redis_cluster_id" {
  description = "ElastiCache Redis cluster ID"
  value       = aws_elasticache_cluster.main.id
}

output "redis_port" {
  description = "ElastiCache Redis port"
  value       = aws_elasticache_cluster.main.port
}

output "redis_connection_string" {
  description = "Redis connection string"
  value       = "redis://${aws_elasticache_cluster.main.cache_nodes[0].address}:${aws_elasticache_cluster.main.port}"
  sensitive   = true
}
