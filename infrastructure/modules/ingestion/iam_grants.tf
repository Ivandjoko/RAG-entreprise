# modules/ingestion/iam_grants.tf
# Complète le rôle créé par modules/security avec l'accès au bucket S3 et à la table
# DynamoDB créés ICI. Placé dans ce module (pas security) pour éviter une dépendance
# circulaire : security ne peut pas connaître leurs ARN avant l'apply d'ingestion.
locals {
  ingestion_role_name = element(split("/", var.ingestion_lambda_role_arn), 1)
}

resource "aws_iam_role_policy" "ingestion_storage_access" {
  name = "ingestion-storage-access"
  role = local.ingestion_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSourceDocuments"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"]
      },
      {
        Sid      = "WriteMetadata"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.metadata.arn
      },
      {
        # Nécessaire pour que le destination_config.on_failure de dlq.tf fonctionne :
        # sans ça, Lambda ne peut pas router les échecs vers la DLQ (AccessDenied silencieux
        # à la configuration, comme on vient de le voir en apply réel).
        Sid      = "SendToDeadLetterQueue"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.ingestion_dlq.arn
      }
    ]
  })
}
