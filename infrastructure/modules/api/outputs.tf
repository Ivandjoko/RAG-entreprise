# modules/api/outputs.tf
output "api_endpoint" {
  value = aws_api_gateway_stage.main.invoke_url
}
output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}
output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.orchestrator.id
}