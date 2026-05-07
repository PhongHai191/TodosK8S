# ── Log Groups ─────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/todoapp/${var.environment}/backend"
  retention_in_days = 30

  tags = { Name = "/todoapp/${var.environment}/backend" }
}

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/todoapp/${var.environment}/nginx"
  retention_in_days = 30

  tags = { Name = "/todoapp/${var.environment}/nginx" }
}

resource "aws_cloudwatch_log_group" "system" {
  name              = "/todoapp/${var.environment}/system"
  retention_in_days = 14

  tags = { Name = "/todoapp/${var.environment}/system" }
}


# ── SNS Topic for alerts ────────────────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── Metric Filters ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_metric_filter" "backend_errors" {
  name           = "${var.project_name}-${var.environment}-backend-errors"
  pattern        = "{ $.level = \"error\" }"
  log_group_name = aws_cloudwatch_log_group.backend.name

  metric_transformation {
    name          = "BackendErrors"
    namespace     = "${var.project_name}/${var.environment}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "login_failures" {
  name           = "${var.project_name}-${var.environment}-login-failures"
  pattern        = "{ $.message = \"login_user_not_found\" || $.message = \"login_wrong_password\" }"
  log_group_name = aws_cloudwatch_log_group.backend.name

  metric_transformation {
    name          = "LoginFailures"
    namespace     = "${var.project_name}/${var.environment}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "health_db_failed" {
  name           = "${var.project_name}-${var.environment}-health-db-failed"
  pattern        = "{ $.message = \"health_db_failed\" }"
  log_group_name = aws_cloudwatch_log_group.backend.name

  metric_transformation {
    name          = "HealthDBFailed"
    namespace     = "${var.project_name}/${var.environment}"
    value         = "1"
    default_value = "0"
  }
}

# ── CloudWatch Alarms ──────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "backend_error_rate" {
  alarm_name          = "${var.project_name}-${var.environment}-backend-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BackendErrors"
  namespace           = "${var.project_name}/${var.environment}"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Backend error rate exceeded 10 errors in 5 minutes"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "login_brute_force" {
  alarm_name          = "${var.project_name}-${var.environment}-login-brute-force"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "LoginFailures"
  namespace           = "${var.project_name}/${var.environment}"
  period              = 300
  statistic           = "Sum"
  threshold           = 20
  alarm_description   = "Possible brute-force: more than 20 login failures in 5 minutes"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "db_health_failure" {
  alarm_name          = "${var.project_name}-${var.environment}-db-health-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthDBFailed"
  namespace           = "${var.project_name}/${var.environment}"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Database health check failed"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
