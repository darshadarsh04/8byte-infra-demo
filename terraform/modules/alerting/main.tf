###############################################################################
# One SNS topic, fanned out to every resource-level alarm below. Alarms that
# map naturally onto a 0-100% scale (CPU, memory, storage used, connection
# pool usage) use var.threshold_percent (80 by default). A few alarms - ALB
# 5xx count, response time, unhealthy host count - don't have a meaningful
# "80%" reading, so those use their own sensible static thresholds instead,
# called out explicitly rather than forcing everything through one number.
#
# Only email is wired up here. To also notify Slack, the standard AWS-native
# path is AWS Chatbot: subscribe a Chatbot Slack channel configuration to
# aws_sns_topic.alerts.arn (console, or aws_chatbot_slack_channel_configuration
# in Terraform) - no custom Lambda forwarder needed.
###############################################################################

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --------------------------------------------------------------------------
# ECS: CPU and memory per service, both against threshold_percent
# --------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  for_each = toset(var.ecs_services)

  alarm_name          = "${each.value}-cpu-high"
  alarm_description   = "${each.value} CPU utilization above ${var.threshold_percent}% for 10 minutes"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.threshold_percent
  period              = 300
  evaluation_periods  = 2 # 10 min sustained, not a single noisy spike
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  for_each = toset(var.ecs_services)

  alarm_name          = "${each.value}-memory-high"
  alarm_description   = "${each.value} memory utilization above ${var.threshold_percent}% for 10 minutes"
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.threshold_percent
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# --------------------------------------------------------------------------
# RDS: CPU, free storage, and connection pool usage - all against threshold_percent
# --------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.rds_instance_id}-cpu-high"
  alarm_description   = "RDS CPU utilization above ${var.threshold_percent}% for 10 minutes"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.threshold_percent
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# FreeStorageSpace is reported in bytes remaining, not percent used - so
# "80% used" becomes "less than 20% of allocated storage remains free".
# Converted here so the alarm still reflects the same 80% policy.
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.rds_instance_id}-storage-low"
  alarm_description   = "RDS free storage below ${100 - var.threshold_percent}% of allocated (i.e. ${var.threshold_percent}% used)"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Average"
  comparison_operator = "LessThanThreshold"
  threshold           = var.rds_allocated_storage_gb * 1073741824 * (1 - var.threshold_percent / 100) # GB -> bytes, then the free-remaining fraction
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.rds_instance_id}-connections-high"
  alarm_description   = "RDS connections above ${var.threshold_percent}% of the assumed ceiling (${var.rds_max_connections})"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.rds_max_connections * (var.threshold_percent / 100)
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# --------------------------------------------------------------------------
# ALB: these three don't map onto "80%" meaningfully, so they use their own
# thresholds instead of var.threshold_percent - noted here rather than forced.
# --------------------------------------------------------------------------

# Any unhealthy target at all is worth knowing about immediately - this isn't
# a utilization metric, so there's no "80% unhealthy" version of this alarm.
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  for_each = var.target_group_arn_suffixes

  alarm_name          = "${var.project_name}-${var.environment}-${each.key}-unhealthy-hosts"
  alarm_description   = "At least one unhealthy target in the ${each.key} target group"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 2 # 2 consecutive minutes, so a single health-check blip during a deploy doesn't page anyone
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# p99 response time above 2s - a latency SLO, not a utilization percentage.
resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  for_each = var.target_group_arn_suffixes

  alarm_name          = "${var.project_name}-${var.environment}-${each.key}-latency-high"
  alarm_description   = "${each.key} p99 response time above 2s for 10 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p99"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 2 # seconds
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# 5xx count is an absolute number, not a percentage of anything meaningful at
# low traffic - 10+ server errors in 5 minutes is worth paging on regardless
# of what fraction of total requests that represents.
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  for_each = var.target_group_arn_suffixes

  alarm_name          = "${var.project_name}-${var.environment}-${each.key}-5xx-high"
  alarm_description   = "${each.key} returning 10+ 5xx responses in 5 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 10
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
