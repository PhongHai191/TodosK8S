variable "aws_region"   { 
    type = string 
    default = "ap-southeast-2" 
}
variable "project_name" { 
    type = string 
    default = "todosk8s" 
}
variable "environment"  { 
    type = string 
    default = "dev" 
}

variable "vpc_cidr"            { type = string }
variable "availability_zones"  { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }

variable "trusted_ip" {
  type        = string
  description = "Trusted CIDR for RDS/Redis ingress, e.g. 1.2.3.4/32"
  validation {
    condition     = can(cidrhost(var.trusted_ip, 0))
    error_message = "trusted_ip must be a valid CIDR block, e.g. 1.2.3.4/32"
  }
}

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

