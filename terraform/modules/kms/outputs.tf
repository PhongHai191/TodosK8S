output "rds_kms_key_arn"      { value = aws_kms_key.rds.arn }
output "rds_kms_key_id"       { value = aws_kms_key.rds.key_id }
output "secrets_kms_key_arn"  { value = aws_kms_key.secrets.arn }
output "secrets_kms_key_id"   { value = aws_kms_key.secrets.key_id }
