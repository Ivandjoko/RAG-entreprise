# modules/ingestion/s3.tf

# checkov:skip=CKV_AWS_144: replication cross-region disproportionnee a ce stade du projet
# (double le cout de stockage + IAM/bucket supplementaires) - a reconsiderer si un vrai
# besoin de DR multi-region apparait.
# checkov:skip=CKV_AWS_18: logging d'acces S3 necessiterait un bucket de logs dedie
# supplementaire - CloudTrail (niveau compte) couvre deja l'audit des API calls sur ce bucket.
resource "aws_s3_bucket" "documents" {
  bucket = "rag-platform-documents-${var.environment}-${data.aws_caller_identity.current.account_id}"
  # Le suffixe account_id garantit l'unicité globale sans avoir besoin d'un
  # random_id supplémentaire à retenir - pratique en multi-comptes puisque
  # chaque compte a un ID différent, aucun risque de collision entre dev/staging/prod

  tags = merge(local.common_tags, { Name = "rag-documents-${var.environment}" })
}

# Bloque tout accès public - non négociable pour un bucket de documents d'entreprise
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Chiffrement avec la clé KMS "data" du module security - cohérent avec
# ce qui protège déjà OpenSearch et DynamoDB
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_data_key_arn
    }
    bucket_key_enabled = true # réduit les appels KMS facturés, sans affaiblir le chiffrement
  }
}

# Versioning : permet de restaurer un document écrasé par erreur,
# et donne un historique en cas d'investigation (quel contenu était indexé à quelle date)
resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Active les notifications EventBridge - c'est ce qui permet à la règle
# aws_cloudwatch_event_rule (déjà écrite) de recevoir les événements "Object Created"
resource "aws_s3_bucket_notification" "documents" {
  bucket      = aws_s3_bucket.documents.id
  eventbridge = true
}

# Lifecycle : les anciennes versions ne s'accumulent pas indéfiniment
# (coût de stockage, et le versioning n'a pas vocation à être un archivage long terme)
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {} # règle applicable à tous les objets du bucket
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # Sans ça, un upload multipart interrompu (retry client, coupure réseau) laisse des
  # parts orphelines facturées indéfiniment - jamais visibles dans le bucket normalement
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Politique de bucket : refuse explicitement tout accès non chiffré en transit
resource "aws_s3_bucket_policy" "documents" {
  bucket = aws_s3_bucket.documents.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.documents.arn,
        "${aws_s3_bucket.documents.arn}/*"
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}