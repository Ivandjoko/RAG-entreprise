# modules/security/kms.tf

# Clé pour les documents sources et l'index vectoriel (données "métier" sensibles)
resource "aws_kms_key" "data" {
  description             = "Chiffrement des documents et de l'index vectoriel RAG - ${var.environment}"
  deletion_window_in_days = 30   # délai de sécurité avant suppression définitive
  enable_key_rotation     = true # rotation automatique annuelle, exigée par la plupart des référentiels (ISO 27001, SOC2)
  policy                  = data.aws_iam_policy_document.kms_data_policy.json
}

resource "aws_kms_alias" "data" {
  name          = "alias/rag-data-${var.environment}"
  target_key_id = aws_kms_key.data.key_id
}

# Clé séparée pour les logs et métadonnées d'audit
resource "aws_kms_key" "audit" {
  description             = "Chiffrement des logs CloudWatch/CloudTrail - ${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_audit_policy.json
}

resource "aws_kms_alias" "audit" {
  name          = "alias/rag-audit-${var.environment}"
  target_key_id = aws_kms_key.audit.key_id
}