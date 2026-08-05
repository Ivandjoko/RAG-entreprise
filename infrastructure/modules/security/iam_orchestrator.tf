# modules/security/iam_orchestrator.tf

resource "aws_iam_role" "orchestrator_lambda" {
  name               = "rag-orchestrator-lambda-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "orchestrator_permissions" {
  # Le grant "aoss:APIAccessAll" (QueryVectorIndex) est accordé depuis modules/retrieval,
  # pas ici : voir la note équivalente dans iam_ingestion.tf (dépendance circulaire évitée).

  statement {
    sid     = "InvokeGenerationModel"
    effect  = "Allow"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [
      "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-*"
    ]
  }

  statement {
    sid     = "ApplyGuardrails"
    effect  = "Allow"
    actions = ["bedrock:ApplyGuardrail"]
    resources = [aws_bedrock_guardrail.main.guardrail_arn]
  }

  statement {
    sid     = "ReadMetadataForFiltering"
    effect  = "Allow"
    actions = ["dynamodb:GetItem", "dynamodb:Query"]  # lecture seule, jamais PutItem/DeleteItem
    resources = [var.metadata_table_arn]
  }

  statement {
    sid     = "DecryptForReading"
    effect  = "Allow"
    actions = ["kms:Decrypt"]  # pas GenerateDataKey : cette Lambda ne chiffre jamais, elle déchiffre pour lire
    resources = [aws_kms_key.data.arn]
  }
}

resource "aws_iam_role_policy" "orchestrator_permissions" {
  name   = "orchestrator-least-privilege"
  role   = aws_iam_role.orchestrator_lambda.id
  policy = data.aws_iam_policy_document.orchestrator_permissions.json
}