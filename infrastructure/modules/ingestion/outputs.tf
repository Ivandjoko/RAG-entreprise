# modules/ingestion/outputs.tf
output "ingestion_lambda_arn" {
  value = aws_lambda_function.ingestion.arn
}
output "ingestion_lambda_function_name" {
  value = aws_lambda_function.ingestion.function_name
}
output "documents_bucket_arn" {
  value = aws_s3_bucket.documents.arn
}
output "documents_bucket_name" {
  value = aws_s3_bucket.documents.id
}
output "metadata_table_arn" {
  value = aws_dynamodb_table.metadata.arn
}
output "metadata_table_name" {
  value = aws_dynamodb_table.metadata.name
}