# modules/retrieval/opensearch_access_policy.tf
#
# AWS distingue 2 ResourceType dans une data access policy OpenSearch Serverless, chacun
# avec son propre jeu de permissions valides et son propre format de Resource :
# - "collection" -> aoss:CreateCollectionItems/UpdateCollectionItems/DescribeCollectionItems...
#                   Resource = ["collection/<name>"]
# - "index"      -> aoss:CreateIndex/UpdateIndex/WriteDocument/ReadDocument/DescribeIndex...
#                   Resource = ["index/<collection-name>/*"]
# CreateIndex/WriteDocument/ReadDocument sont des permissions d'INDEX, pas de collection -
# les mettre sous ResourceType "collection" est rejeté par l'API (ValidationException).
resource "aws_opensearchserverless_access_policy" "collection_access" {
  name = "rag-collection-access-${var.environment}"
  type = "data"
  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${var.collection_name}"]
          Permission   = ["aoss:CreateCollectionItems", "aoss:UpdateCollectionItems", "aoss:DescribeCollectionItems"]
        },
        {
          ResourceType = "index"
          Resource     = ["index/${var.collection_name}/*"]
          # ReadDocument est necessaire ici : avant de reindexer, indexer.py recherche les
          # anciens chunks du meme doc_id (pas d'_id personnalise possible sur VECTORSEARCH,
          # donc pas de delete_by_query -> on cherche puis on supprime par _id auto-genere).
          Permission = ["aoss:CreateIndex", "aoss:UpdateIndex", "aoss:WriteDocument", "aoss:DescribeIndex", "aoss:ReadDocument"]
        }
      ]
      Principal = [var.ingestion_lambda_role_arn] # écriture (+ lecture pour la dedup) réservée à l'ingestion
    },
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${var.collection_name}"]
          Permission   = ["aoss:DescribeCollectionItems"]
        },
        {
          ResourceType = "index"
          Resource     = ["index/${var.collection_name}/*"]
          Permission   = ["aoss:DescribeIndex", "aoss:ReadDocument"]
        }
      ]
      Principal = [var.orchestrator_lambda_role_arn] # lecture seule pour l'orchestrateur
    }
  ])
}
