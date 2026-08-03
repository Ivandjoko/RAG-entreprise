# modules/ingestion/dlq.tf
resource "aws_sqs_queue" "ingestion_dlq" {
  name                      = "rag-ingestion-dlq-${var.environment}"
  message_retention_seconds = 1209600  # 14 jours pour investiguer avant expiration
  kms_master_key_id         = var.kms_data_key_arn
}

resource "aws_lambda_function_event_invoke_config" "ingestion_retry" {
  function_name                = aws_lambda_function.ingestion.function_name
  maximum_retry_attempts       = 2
  destination_config {
    on_failure {
      destination = aws_sqs_queue.ingestion_dlq.arn
    }
  }
}