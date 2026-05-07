variable "project_name"           { type = string }
variable "environment"             { type = string }
variable "public_subnet_ids"  { type = list(string) }
variable "redis_sg_id"             { type = string }
