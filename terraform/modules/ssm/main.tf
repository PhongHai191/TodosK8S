locals {
  path = "/todoapp/${var.environment}"
}

resource "aws_ssm_parameter" "db_host" {
  name  = "${local.path}/DB_HOST"
  type  = "String"
  value = var.db_host
}

resource "aws_ssm_parameter" "db_user" {
  name   = "${local.path}/DB_USER"
  type   = "SecureString"
  value  = var.db_user
  key_id = var.kms_key_arn
}

resource "aws_ssm_parameter" "db_password" {
  name   = "${local.path}/DB_PASS"
  type   = "SecureString"
  value  = var.db_password
  key_id = var.kms_key_arn
}

resource "aws_ssm_parameter" "db_name" {
  name  = "${local.path}/DB_NAME"
  type  = "String"
  value = var.db_name
}

resource "aws_ssm_parameter" "db_secret_name" {
  name  = "${local.path}/DB_SECRET_NAME"
  type  = "String"
  value = var.db_secret_name
}

resource "aws_ssm_parameter" "redis_host" {
  name  = "${local.path}/REDIS_HOST"
  type  = "String"
  value = var.redis_host
}

resource "aws_ssm_parameter" "jwt_access_secret" {
  name   = "${local.path}/JWT_ACCESS_SECRET"
  type   = "SecureString"
  value  = var.jwt_access_secret
  key_id = var.kms_key_arn
}

resource "aws_ssm_parameter" "jwt_refresh_secret" {
  name   = "${local.path}/JWT_REFRESH_SECRET"
  type   = "SecureString"
  value  = var.jwt_refresh_secret
  key_id = var.kms_key_arn
}

resource "aws_ssm_parameter" "access_expire" {
  name  = "${local.path}/ACCESS_EXPIRE"
  type  = "String"
  value = var.access_expire
}

resource "aws_ssm_parameter" "refresh_expire" {
  name  = "${local.path}/REFRESH_EXPIRE"
  type  = "String"
  value = var.refresh_expire
}

resource "aws_ssm_parameter" "aws_region" {
  name  = "${local.path}/AWS_REGION"
  type  = "String"
  value = var.aws_region
}

resource "aws_ssm_parameter" "s3_bucket" {
  name  = "${local.path}/AWS_S3_BUCKET"
  type  = "String"
  value = var.s3_bucket_name
}

resource "aws_ssm_parameter" "grafana_admin_password" {
  name   = "${local.path}/GRAFANA_ADMIN_PASSWORD"
  type   = "SecureString"
  value  = var.grafana_admin_password
  key_id = var.kms_key_arn
}
