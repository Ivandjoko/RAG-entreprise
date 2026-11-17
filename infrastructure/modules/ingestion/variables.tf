# modules/ingestion/variables.tf
variable "environment" {
  type = string
}

variable "kms_data_key_arn" {
  type        = string
  description = "Clé KMS utilisée pour chiffrer la DLQ (module security)"
}

variable "ingestion_lambda_role_arn" {
  type        = string
  description = "ARN du rôle IAM de la Lambda d'ingestion (module security)"
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "lambda_security_group_id" {
  type = string
}

variable "opensearch_collection_endpoint" {
  type = string
}

variable "opensearch_index_name" {
  type = string
}

variable "kms_audit_key_arn" {
  type        = string
  description = "Clé KMS utilisée pour chiffrer le log group CloudWatch de la Lambda"
}

variable "log_retention_days" {
  type    = number
  default = 30
}
