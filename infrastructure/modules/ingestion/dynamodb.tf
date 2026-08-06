# modules/ingestion/dynamodb.tf

resource "aws_dynamodb_table" "metadata" {
  name         = "rag-platform-metadata-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"   # pas de capacité à dimensionner à l'avance, adapté à un trafic imprévisible
  hash_key     = "doc_id"

  attribute {
    name = "doc_id"
    type = "S"
  }

  # Index secondaire pour interroger par statut (utile pour un dashboard
  # "documents en erreur" mentionné dans le runbook du README)
  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true   # permet de restaurer la table à un instant T en cas de corruption/erreur d'écriture massive
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_data_key_arn
  }

  tags = merge(local.common_tags, { Name = "rag-metadata-${var.environment}" })
}