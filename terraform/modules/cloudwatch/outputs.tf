output "backend_log_group_name" { value = aws_cloudwatch_log_group.backend.name }
output "nginx_log_group_name"   { value = aws_cloudwatch_log_group.nginx.name }
output "system_log_group_name"  { value = aws_cloudwatch_log_group.system.name }
output "alerts_topic_arn"       { value = aws_sns_topic.alerts.arn }
