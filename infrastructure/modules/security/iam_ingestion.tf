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
  # Les grants S3 (ReadSourceDocuments) et DynamoDB (WriteMetadata) sont accordés depuis
  # modules/ingestion, qui possède le bucket et la table - même raison que le grant aoss
  # ci-dessous (dépendance circulaire évitée).

  # Cette Lambda est attachée au VPC (vpc_config) : sans ces permissions EC2, AWS Lambda
  # ne peut pas créer les ENI nécessaires pour joindre les subnets privés - équivalent de
  # la policy managée AWSLambdaVPCAccessExecutionRole, appliqué ici en scope custom.
  statement {
    sid    = "VPCNetworkInterface"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses"
    ]
    resources = ["*"] # ces actions EC2 ne supportent pas le scoping par ARN de ressource
  }

  statement {
    sid       = "XRayTracing"
    effect    = "Allow"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"] # X-Ray ne supporte pas le scoping par ARN sur ces actions
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

  # Le grant "aoss:APIAccessAll" (WriteVectorIndex) est accordé depuis modules/retrieval,
  # pas ici : ce module ne connaît pas encore l'ARN de la collection au moment de son
  # propre apply (elle est créée par retrieval), et l'inverse créerait une dépendance
  # circulaire entre les deux modules.

  statement {
    sid       = "DecryptData"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.data.arn]
  }

  # Logs CloudWatch : ce rôle est aussi utilisé par la Lambda index_bootstrap (modules/retrieval),
  # d'où le 2e log group - voir la note dans index_bootstrap.tf.
  statement {
    sid     = "WriteOwnLogs"
    effect  = "Allow"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/rag-ingestion-${var.environment}:*",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/rag-index-bootstrap-${var.environment}:*"
    ]
  }
}

resource "aws_iam_role_policy" "ingestion_permissions" {
  name   = "ingestion-least-privilege"
  role   = aws_iam_role.ingestion_lambda.id
  policy = data.aws_iam_policy_document.ingestion_permissions.json
}