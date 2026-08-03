# modules/security/opensearch_access_policy.tf
resource "aws_opensearchserverless_access_policy" "collection_access" {
  name = "rag-collection-access-${var.environment}"
  type = "data"
  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${var.opensearch_collection_name}"]
          Permission   = ["aoss:CreateIndex", "aoss:UpdateIndex", "aoss:WriteDocument"]
        }
      ]
      Principal = [aws_iam_role.ingestion_lambda.arn]   # écriture réservée à l'ingestion
    },
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${var.opensearch_collection_name}"]
          Permission   = ["aoss:DescribeIndex", "aoss:ReadDocument"]
        }
      ]
      Principal = [aws_iam_role.orchestrator_lambda.arn]  # lecture seule pour l'orchestrateur
    }
  ])
}