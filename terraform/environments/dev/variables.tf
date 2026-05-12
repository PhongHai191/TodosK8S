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

variable "trusted_ips" {
  type        = list(string)
  description = "Trusted CIDRs for RDS ingress (dev machines), e.g. [\"1.2.3.4/32\"]"
  validation {
    condition     = alltrue([for ip in var.trusted_ips : can(cidrhost(ip, 0))])
    error_message = "Each entry in trusted_ips must be a valid CIDR block, e.g. 1.2.3.4/32"
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

