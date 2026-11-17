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
output "orchestrator_lambda_arn" {
  value = aws_lambda_function.orchestrator.arn
}
output "orchestrator_lambda_function_name" {
  value = aws_lambda_function.orchestrator.function_name
}
output "orchestrator_lambda_invoke_arn" {
  value = aws_lambda_function.orchestrator.invoke_arn
}
