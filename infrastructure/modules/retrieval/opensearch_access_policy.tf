# modules/retrieval/opensearch_access_policy.tf

resource "aws_opensearchserverless_access_policy" "collection_access" {
  name = "rag-collection-access-${var.environment}"
  type = "data"
  policy = jsonencode([
    {
      Rules = [{
        ResourceType = "collection"
        Resource     = ["collection/${var.collection_name}"]
        Permission   = ["aoss:CreateIndex", "aoss:UpdateIndex", "aoss:WriteDocument", "aoss:DescribeIndex"]
      }]
      Principal = [var.ingestion_lambda_role_arn]   # écriture réservée à l'ingestion
    },
    {
      Rules = [{
        ResourceType = "collection"
        Resource     = ["collection/${var.collection_name}"]
        Permission   = ["aoss:DescribeIndex", "aoss:ReadDocument"]
      }]
      Principal = [var.orchestrator_lambda_role_arn]  # lecture seule pour l'orchestrateur
    }
  ])
}