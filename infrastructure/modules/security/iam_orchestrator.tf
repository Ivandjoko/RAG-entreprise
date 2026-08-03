# modules/security/iam_orchestrator.tf

resource "aws_iam_role" "orchestrator_lambda" {
  name               = "rag-orchestrator-lambda-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "orchestrator_permissions" {
  statement {
    sid     = "QueryVectorIndex"
    effect  = "Allow"
    actions = ["aoss:APIAccessAll"]
    resources = [var.opensearch_collection_arn]
    # note : même verbe qu'en ingestion, mais le rôle diffère - l'AZ Collection Policy
    # OpenSearch (pas Terraform IAM) est ce qui distingue lecture/écriture ici, voir plus bas
  }

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
    resources = [var.kms_data_key_arn]
  }
}

resource "aws_iam_role_policy" "orchestrator_permissions" {
  name   = "orchestrator-least-privilege"
  role   = aws_iam_role.orchestrator_lambda.id
  policy = data.aws_iam_policy_document.orchestrator_permissions.json
}