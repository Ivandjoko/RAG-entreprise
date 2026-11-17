# modules/security/iam_orchestrator.tf

resource "aws_iam_role" "orchestrator_lambda" {
  name                 = "rag-orchestrator-lambda-${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume_role.json
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn
}

data "aws_iam_policy_document" "orchestrator_permissions" {
  # Le grant "aoss:APIAccessAll" (QueryVectorIndex) est accordé depuis modules/retrieval,
  # pas ici : voir la note équivalente dans iam_ingestion.tf (dépendance circulaire évitée).

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
    sid     = "InvokeGenerationModel"
    effect  = "Allow"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [
      # eu-west-3 n'a pas d'accès "In-Region" à Claude Sonnet 4.6 sur Bedrock : on passe
      # par le profil d'inférence cross-region "eu", qui route vers le modèle sous-jacent
      # dans l'une des régions du groupe géo "eu" (eu-central-1, eu-north-1, eu-west-1...).
      # Les deux ARN sont nécessaires : celui du profil ET celui du modèle sous-jacent.
      "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/eu.anthropic.claude-sonnet-4-6",
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-6",
      # Titan Embed V2 (embed_query) - oublié lors du premier passage de cette policy
      # (seule la génération avait été couverte). Pas de grant Cohere/Amazon Rerank : aucun
      # modèle de rerank Bedrock n'est disponible depuis eu-west-3 (voir retrieval.py).
      "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
    ]
  }

  # Claude (Anthropic) est un modèle tiers distribué via AWS Marketplace - contrairement à
  # Titan (natif AWS), le premier InvokeModel nécessite que le rôle appelant puisse lui-même
  # vérifier/finaliser l'abonnement Marketplace, pas seulement bedrock:InvokeModel.
  statement {
    sid       = "MarketplaceModelSubscription"
    effect    = "Allow"
    actions   = ["aws-marketplace:ViewSubscriptions", "aws-marketplace:Subscribe"]
    resources = ["*"] # ces actions Marketplace ne supportent pas le scoping par ARN
  }

  statement {
    sid       = "ApplyGuardrails"
    effect    = "Allow"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [aws_bedrock_guardrail.main.guardrail_arn]
  }

  # Le grant DynamoDB (ReadUserPermissions) est accordé depuis modules/retrieval, qui
  # possède la table user_permissions - même raison que le grant aoss ci-dessus.

  statement {
    sid       = "DecryptForReading"
    effect    = "Allow"
    actions   = ["kms:Decrypt"] # pas GenerateDataKey : cette Lambda ne chiffre jamais, elle déchiffre pour lire
    resources = [aws_kms_key.data.arn]
  }
  statement {
    sid       = "XRayTracing"
    effect    = "Allow"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"] # X-Ray ne supporte pas le scoping par ARN sur ces actions
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