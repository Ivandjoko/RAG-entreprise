# modules/retrieval/opensearch_collection.tf

resource "aws_opensearchserverless_collection" "vectors" {
  name = var.collection_name
  type = "VECTORSEARCH"   # type spécifique pour la recherche vectorielle (vs "SEARCH" ou "TIMESERIES")

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network
  ]
}