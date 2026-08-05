# modules/security/variables.tf
variable "environment" {
  type        = string
  description = "dev, staging ou prod"
}

variable "guardrail_strength" {
  type        = string
  description = "Sévérité des filtres de contenu Bedrock Guardrails (LOW, MEDIUM, HIGH)"
}

variable "aws_region" {
  type        = string
  description = "Région AWS où sont déployées les ressources (utilisée pour construire des ARNs)"
}

# NOTE: ces 2 variables sont nécessaires pour que le module soit syntaxiquement valide,
# mais rien ne les alimente encore en amont : les ressources documents_bucket / metadata_table
# n'existent pas encore côté Terraform (voir rapport d'audit).
variable "documents_bucket_arn" {
  type        = string
  description = "ARN du bucket S3 des documents sources (créé par le module ingestion)"
}

variable "metadata_table_arn" {
  type        = string
  description = "ARN de la table DynamoDB de métadonnées (créée par le module ingestion)"
}
