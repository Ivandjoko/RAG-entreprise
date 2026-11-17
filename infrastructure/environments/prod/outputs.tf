# environments/dev/outputs.tf
output "documents_bucket_name" {
  value = module.ingestion.documents_bucket_name
}

output "api_endpoint" {
  value = module.api.api_endpoint
}

output "user_pool_id" {
  value = module.api.user_pool_id
}

output "user_pool_client_id" {
  value = module.api.user_pool_client_id
}

output "opensearch_collection_endpoint" {
  value = module.retrieval.collection_endpoint
}

output "orchestrator_lambda_function_name" {
  value = module.retrieval.orchestrator_lambda_function_name
}

output "ingestion_lambda_function_name" {
  value = module.ingestion.ingestion_lambda_function_name
}
