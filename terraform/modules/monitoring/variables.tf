variable "project_name"         { type = string }
variable "environment"          { type = string }
variable "ami_id"               { type = string }
variable "kms_key_arn"          { type = string }
variable "public_subnet_id"     { type = string }
variable "monitoring_sg_id"     { type = string }
variable "ec2_instance_profile" { type = string }
