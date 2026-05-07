variable "project_name" { type = string }
variable "environment"  { type = string }

variable "alert_email" {
  type        = string
  default     = ""
  description = "Email address for CloudWatch alarm notifications. Leave empty to skip."
}
