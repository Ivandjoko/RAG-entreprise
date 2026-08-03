# modules/ingestion/eventbridge.tf (rappel de l'infra qui pilote cette Lambda)

resource "aws_cloudwatch_event_rule" "document_uploaded" {
  name = "rag-document-uploaded-${var.environment}"
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [var.documents_bucket_name] }
    }
  })
}

resource "aws_cloudwatch_event_target" "trigger_ingestion" {
  rule = aws_cloudwatch_event_rule.document_uploaded.name
  arn  = aws_lambda_function.ingestion.arn
}