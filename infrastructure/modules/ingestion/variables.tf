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

# NOTE: bloqué en amont, aucune ressource S3/DynamoDB n'existe encore pour ces deux-là
# (voir rapport d'audit) - le module reste syntaxiquement valide mais pas encore appelable.
variable "documents_bucket_name" {
  type        = string
  description = "Nom du bucket S3 des documents sources (déclenche l'EventBridge rule)"
}

variable "metadata_table_name" {
  type        = string
  description = "Nom de la table DynamoDB de métadonnées"
}
