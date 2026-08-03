# modules/security/iam_ingestion.tf

resource "aws_iam_role" "ingestion_lambda" {
  name               = "rag-ingestion-lambda-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  # ↑ cette policy dit "seul le service Lambda peut endosser ce rôle" (voir plus bas)
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Policy scopée : uniquement le bucket S3 du projet, en lecture seule
data "aws_iam_policy_document" "ingestion_permissions" {
  statement {
    sid     = "ReadSourceDocuments"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      var.documents_bucket_arn,
      "${var.documents_bucket_arn}/*"
    ]
  }

  statement {
    sid     = "WriteMetadata"
    effect  = "Allow"
    actions = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [var.metadata_table_arn]  # jamais "*", toujours l'ARN précis de LA table
  }

  statement {
    sid     = "GenerateEmbeddings"
    effect  = "Allow"
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
      # scopé au modèle d'embedding précis, pas "tous les modèles Bedrock"
    ]
  }

  statement {
    sid     = "WriteVectorIndex"
    effect  = "Allow"
    actions = ["aoss:APIAccessAll"]  # OpenSearch Serverless (aoss = Amazon OpenSearch Serverless)
    resources = [var.opensearch_collection_arn]
  }

  statement {
    sid     = "DecryptData"
    effect  = "Allow"
    actions = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_data_key_arn]
  }

  # Logs CloudWatch : chaque Lambda ne peut écrire que dans SON propre log group
  statement {
    sid     = "WriteOwnLogs"
    effect  = "Allow"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/rag-ingestion-${var.environment}:*"]
  }
}

resource "aws_iam_role_policy" "ingestion_permissions" {
  name   = "ingestion-least-privilege"
  role   = aws_iam_role.ingestion_lambda.id
  policy = data.aws_iam_policy_document.ingestion_permissions.json
}