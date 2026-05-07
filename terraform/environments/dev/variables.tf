variable "aws_region"   { 
    type = string 
    default = "ap-southeast-2" 
}
variable "project_name" { 
    type = string 
    default = "awstodo" 
}
variable "environment"  { 
    type = string 
    default = "dev" 
}

variable "vpc_cidr"            { type = string }
variable "availability_zones"  { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }
variable "private_app_cidrs"   { type = list(string) }
variable "private_db_cidrs"    { type = list(string) }

variable "trusted_ip"    { type = string }

variable "db_username"       { 
    type = string 
    sensitive = true 
}
variable "db_password"       { 
    type = string 
    sensitive = true 
}
variable "db_name"           { type = string }
variable "db_instance_class" { type = string }

variable "s3_bucket_name" { type = string }
variable "github_repo"    { type = string }

variable "jwt_access_secret" {
  type      = string
  sensitive = true
}
variable "jwt_refresh_secret" {
  type      = string
  sensitive = true
}
