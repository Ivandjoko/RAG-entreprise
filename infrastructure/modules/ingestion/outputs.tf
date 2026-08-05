# modules/ingestion/outputs.tf
output "ingestion_lambda_arn" {
  value = aws_lambda_function.ingestion.arn
}
output "ingestion_lambda_function_name" {
  value = aws_lambda_function.ingestion.function_name
}
