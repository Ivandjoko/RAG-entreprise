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

  # Le grant DynamoDB (ReadUserPermissions) est accordé depuis modules/retrieval, qui
  # possède la table user_permissions - même raison que le grant aoss ci-dessus.

  statement {
    sid     = "DecryptForReading"
    effect  = "Allow"
    actions = ["kms:Decrypt"]  # pas GenerateDataKey : cette Lambda ne chiffre jamais, elle déchiffre pour lire
    resources = [aws_kms_key.data.arn]
  }
  statement {
    sid     = "XRayTracing"
    effect  = "Allow"
    actions = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]  # X-Ray ne supporte pas le scoping par ARN sur ces actions
  }

  # Logs d'exécution Lambda + log group d'audit applicatif utilisé par audit.py
  # (sans ça, chaque requête plante sur AccessDenied au moment de logger l'audit)
  statement {
    sid     = "WriteLogs"
    effect  = "Allow"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/rag-orchestrator-${var.environment}:*",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rag-platform/query-audit:*"
    ]
  }
}

resource "aws_iam_role_policy" "orchestrator_permissions" {
  name   = "orchestrator-least-privilege"
  role   = aws_iam_role.orchestrator_lambda.id
  policy = data.aws_iam_policy_document.orchestrator_permissions.json
}