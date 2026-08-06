# modules/retrieval/dynamodb.tf
# Table séparée de modules/ingestion/dynamodb.tf (table "metadata", clé doc_id) :
# celle-ci mappe user_id -> groupes de permissions, un schéma de clé totalement
# différent. Les conflater dans une seule table (comme c'était le cas avant que
# les deux tables n'existent réellement) casse au premier get_item : DynamoDB
# exige que la Key fournie corresponde exactement au hash_key déclaré de la table.
resource "aws_dynamodb_table" "user_permissions" {
  name         = "rag-platform-user-permissions-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_data_key_arn
  }

  tags = merge(local.common_tags, { Name = "rag-user-permissions-${var.environment}" })
}
