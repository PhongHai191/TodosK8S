output "vpc_id"                  { value = module.network.vpc_id }
output "public_subnet_ids"       { value = module.network.public_subnet_ids }
output "private_app_subnet_ids"  { value = module.network.private_app_subnet_ids }
output "private_db_subnet_ids"   { value = module.network.private_db_subnet_ids }
output "redis_endpoint"          { value = module.redis.redis_endpoint }
output "rds_endpoint"            {
  value     = module.rds.rds_endpoint
  sensitive = true
}
output "s3_bucket_name"          { value = module.s3.bucket_name }
output "github_actions_role_arn" { value = module.iam.github_actions_role_arn }
output "rds_kms_key_arn"         { value = module.kms.rds_kms_key_arn }
output "secrets_kms_key_arn"     { value = module.kms.secrets_kms_key_arn }
output "db_credentials_secret_arn" { value = module.rds.db_credentials_secret_arn }
