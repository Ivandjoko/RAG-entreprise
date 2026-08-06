# modules/retrieval/iam_grants.tf
# Complète les rôles créés par modules/security avec l'accès data-plane à CETTE collection.
# Placé ici (et non dans security) pour éviter une dépendance circulaire entre les deux
# modules : la collection n'existe qu'après l'apply de retrieval, security ne peut donc
# pas connaître son ARN à l'avance.
locals {
  ingestion_role_name    = element(split("/", var.ingestion_lambda_role_arn), 1)
  orchestrator_role_name = element(split("/", var.orchestrator_lambda_role_arn), 1)
}

resource "aws_iam_role_policy" "ingestion_write_vector_index" {
  name = "ingestion-write-vector-index"
  role = local.ingestion_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "WriteVectorIndex"
      Effect    = "Allow"
      Action    = ["aoss:APIAccessAll"]
      Resource  = aws_opensearchserverless_collection.vectors.arn
    }]
  })
}

resource "aws_iam_role_policy" "orchestrator_query_vector_index" {
  name = "orchestrator-query-vector-index"
  role = local.orchestrator_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "QueryVectorIndex"
      Effect    = "Allow"
      Action    = ["aoss:APIAccessAll"]
      Resource  = aws_opensearchserverless_collection.vectors.arn
    }]
  })
}

# Lecture seule de la table user_permissions (créée dans ce module, voir dynamodb.tf) -
# même raison que les grants aoss ci-dessus (pas de dépendance circulaire vers security).
resource "aws_iam_role_policy" "orchestrator_read_user_permissions" {
  name = "orchestrator-read-user-permissions"
  role = local.orchestrator_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadUserPermissions"
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem"]
      Resource = aws_dynamodb_table.user_permissions.arn
    }]
  })
}
