output "rds_endpoint" {
  value     = aws_db_instance.main.endpoint
  sensitive = true
}
output "rds_port"                   { value = aws_db_instance.main.port }
output "rds_instance_id"            { value = aws_db_instance.main.id }
output "rds_db_name"                { value = aws_db_instance.main.db_name }
output "db_credentials_secret_arn"  { value = aws_secretsmanager_secret.db_credentials.arn }
