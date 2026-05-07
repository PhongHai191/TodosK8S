variable "environment"      { type = string }
variable "kms_key_arn"      { type = string }
variable "aws_region"       { type = string }
variable "s3_bucket_name"   { type = string }
variable "db_name"          { type = string }
variable "db_secret_name"   { type = string }
variable "redis_host"       { type = string }

variable "db_host" {
  type      = string
  sensitive = true
}
variable "db_user" {
  type      = string
  sensitive = true
}
variable "db_password" {
  type      = string
  sensitive = true
}

variable "jwt_access_secret" {
  type      = string
  sensitive = true
}
variable "jwt_refresh_secret" {
  type      = string
  sensitive = true
}

variable "access_expire" {
  type    = string
  default = "15m"
}
variable "refresh_expire" {
  type    = string
  default = "7d"
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}
