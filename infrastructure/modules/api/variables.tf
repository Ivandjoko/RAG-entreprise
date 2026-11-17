# modules/api/variables.tf
variable "environment" {
  type = string
}

variable "orchestrator_lambda_invoke_arn" {
  type = string
}

variable "orchestrator_lambda_function_name" {
  type = string
}

variable "kms_audit_key_arn" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "throttling_rate_limit" {
  type = number
}

variable "throttling_burst_limit" {
  type = number
}

variable "permission_groups" {
  type = list(string)
}

variable "waf_rate_limit_per_ip" {
  type = number
}

variable "blocked_countries" {
  type    = list(string)
  default = []
}

variable "enable_waf" {
  type        = bool
  default     = true
  description = "Si false, le Web ACL et son association à l'API Gateway ne sont pas créés."
}
