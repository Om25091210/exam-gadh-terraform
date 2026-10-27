variable "name" { type = string }
variable "alert_email" { type = string }
variable "monthly_budget_usd" { type = number }
variable "instance_id" { type = string }
variable "db_identifier" { type = string }
variable "db_arn" { type = string }

# --- schedule (dev only): stop EC2 + RDS outside working hours ---------------------------------
variable "enable_schedule" {
  type    = bool
  default = false
}
variable "schedule_timezone" {
  type    = string
  default = "Asia/Kolkata"
}
variable "start_cron" {
  type    = string
  default = "cron(45 7 ? * MON-SAT *)"
}
variable "stop_cron" {
  type    = string
  default = "cron(0 23 ? * * *)"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- alerts ------------------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # recipient must confirm the subscription email
}

resource "aws_cloudwatch_metric_alarm" "ec2_system_recover" {
  alarm_name          = "${var.name}-ec2-system-status"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = ["arn:aws:automate:${data.aws_region.current.name}:ec2:recover", aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "ec2_instance_status" {
  alarm_name          = "${var.name}-ec2-instance-status"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "ec2_cpu" {
  alarm_name          = "${var.name}-ec2-cpu-high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.name}-rds-free-storage-low"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 2147483648 # 2 GiB
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name}-rds-cpu-high"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.name}-rds-connections-high"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

# --- cost control ------------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = [60, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# --- dev schedule ------------------------------------------------------------------------------
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    actions   = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = ["arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/${var.instance_id}"]
  }
  statement {
    actions   = ["rds:StartDBInstance", "rds:StopDBInstance"]
    resources = [var.db_arn]
  }
}

resource "aws_iam_role" "scheduler" {
  count              = var.enable_schedule ? 1 : 0
  name               = "${var.name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

resource "aws_iam_role_policy" "scheduler" {
  count  = var.enable_schedule ? 1 : 0
  name   = "start-stop"
  role   = aws_iam_role.scheduler[0].id
  policy = data.aws_iam_policy_document.scheduler.json
}

locals {
  actions = var.enable_schedule ? {
    ec2-start = { cron = var.start_cron, arn = "arn:aws:scheduler:::aws-sdk:ec2:startInstances", input = jsonencode({ InstanceIds = [var.instance_id] }) }
    ec2-stop  = { cron = var.stop_cron, arn = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances", input = jsonencode({ InstanceIds = [var.instance_id] }) }
    rds-start = { cron = var.start_cron, arn = "arn:aws:scheduler:::aws-sdk:rds:startDBInstance", input = jsonencode({ DbInstanceIdentifier = var.db_identifier }) }
    rds-stop  = { cron = var.stop_cron, arn = "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance", input = jsonencode({ DbInstanceIdentifier = var.db_identifier }) }
  } : {}
}

resource "aws_scheduler_schedule" "this" {
  for_each                     = local.actions
  name                         = "${var.name}-${each.key}"
  schedule_expression          = each.value.cron
  schedule_expression_timezone = var.schedule_timezone
  flexible_time_window { mode = "OFF" }
  target {
    arn      = each.value.arn
    role_arn = aws_iam_role.scheduler[0].arn
    input    = each.value.input
  }
}

output "alerts_topic_arn" { value = aws_sns_topic.alerts.arn }
