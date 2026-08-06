# modules/ingestion/eventbridge.tf (rappel de l'infra qui pilote cette Lambda)

resource "aws_cloudwatch_event_rule" "document_uploaded" {
  name = "rag-document-uploaded-${var.environment}"
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.documents.id] }
    }
  })
}

resource "aws_cloudwatch_event_target" "trigger_ingestion" {
  rule = aws_cloudwatch_event_rule.document_uploaded.name
  arn  = aws_lambda_function.ingestion.arn
}
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.document_uploaded.arn
}