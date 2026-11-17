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
