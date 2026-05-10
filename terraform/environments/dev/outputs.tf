# ── Điền vào k8s/todoapp/secret.yaml sau khi apply ────────────────────────────
output "rds_endpoint" {
  value     = module.rds.rds_endpoint
  sensitive = true
}
output "redis_endpoint"  { value = module.redis.redis_endpoint }
output "s3_bucket_name"  { value = module.s3.bucket_name }

# ── Điền vào GitHub Secrets ───────────────────────────────────────────────────
output "github_actions_role_arn" { value = module.iam.github_actions_role_arn }
# ── AWS credentials cho backend pod (S3 avatar upload) ───────────────────────
output "backend_s3_access_key_id" {
  value     = aws_iam_access_key.backend_s3.id
}
output "backend_s3_secret_access_key" {
  value     = aws_iam_access_key.backend_s3.secret
  sensitive = true
}
