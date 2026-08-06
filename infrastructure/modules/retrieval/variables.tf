# modules/retrieval/variables.tf
variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "lambda_security_group_id" {
  type = string
}

variable "vpc_endpoints_security_group_id" {
  type = string
}

variable "collection_name" {
  type    = string
  default = "rag-vectors"
}

variable "index_name" {
  type    = string
  default = "rag-chunks"
}

variable "kms_data_key_arn" {
  type = string
}

variable "ingestion_lambda_role_arn" {
  type = string
}

variable "orchestrator_lambda_role_arn" {
  type = string
}

variable "guardrail_id" {
  type = string
}

variable "guardrail_version" {
  type = string
}

variable "opensearch_instance_type" {
  type        = string
  default     = "OCU"
  description = "Sans effet pour l'instant : OpenSearch Serverless ne se dimensionne pas par type d'instance (conservé pour compat descendante de l'appelant)."
}

variable "kms_audit_key_arn" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}