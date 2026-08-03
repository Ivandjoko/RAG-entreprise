# modules/retrieval/outputs.tf
output "collection_arn" {
  value = aws_opensearchserverless_collection.vectors.arn
}
output "collection_endpoint" {
  value = aws_opensearchserverless_collection.vectors.collection_endpoint
}
output "index_name" {
  value = var.index_name
}