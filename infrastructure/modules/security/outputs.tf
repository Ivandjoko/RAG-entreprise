# modules/security/outputs.tf
output "kms_data_key_arn" {
  value = aws_kms_key.data.arn
}
output "kms_audit_key_arn" {
  value = aws_kms_key.audit.arn
}
output "ingestion_lambda_role_arn" {
  value = aws_iam_role.ingestion_lambda.arn
}
output "orchestrator_lambda_role_arn" {
  value = aws_iam_role.orchestrator_lambda.arn
}
output "guardrail_id" {
  value = aws_bedrock_guardrail.main.guardrail_id
}
output "guardrail_version" {
  value = aws_bedrock_guardrail_version.main.version
}