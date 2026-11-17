# modules/evaluation/scheduled_eval.tf
resource "aws_cloudwatch_event_rule" "weekly_ragas_eval" {
  name                = "rag-weekly-evaluation-${var.environment}"
  schedule_expression = "rate(7 days)"
}

resource "aws_cloudwatch_event_target" "trigger_eval" {
  rule = aws_cloudwatch_event_rule.weekly_ragas_eval.name
  arn  = aws_sfn_state_machine.evaluation_pipeline.arn
  role_arn = var.eventbridge_invoke_role_arn
}