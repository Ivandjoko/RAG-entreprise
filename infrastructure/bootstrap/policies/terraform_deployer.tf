# infrastructure/bootstrap/policies/terraform_deployer.tf

data "aws_iam_policy_document" "terraform_deployer" {
  # Réseau
  statement {
    sid    = "Networking"
    effect = "Allow"
    actions = [
      "ec2:*Vpc*", "ec2:*Subnet*", "ec2:*RouteTable*", "ec2:*SecurityGroup*",
      "ec2:*VpcEndpoint*", "ec2:DescribeAvailabilityZones", "ec2:*Tags*"
    ]
    resources = ["*"] # EC2 ne supporte pas toujours le scoping par ARN pour ces actions de lecture/gestion réseau
  }

  # Stockage et données
  statement {
    sid     = "Storage"
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::rag-platform-*",
      "arn:aws:s3:::rag-platform-*/*"
    ]
  }

  statement {
    sid       = "Database"
    effect    = "Allow"
    actions   = ["dynamodb:*"]
    resources = ["arn:aws:dynamodb:*:*:table/rag-platform-*"]
  }

  # IA / recherche
  statement {
    sid    = "AIServices"
    effect = "Allow"
    actions = [
      "bedrock:*",
      "aoss:*"
    ]
    resources = ["*"] # Bedrock et OpenSearch Serverless exposent peu d'ARN scopables sur les actions de gestion
  }

  # Compute
  # "rag-*" et non "rag-platform-*" : les fonctions reelles sont nommees rag-ingestion-*,
  # rag-orchestrator-*, rag-index-bootstrap-* (jamais "rag-platform-*") - incoherence de
  # nommage decouverte au premier vrai apply via le role CI scope (jamais exerce avant).
  statement {
    sid       = "Compute"
    effect    = "Allow"
    actions   = ["lambda:*"]
    resources = ["arn:aws:lambda:*:*:function:rag-*"]
  }

  # API et auth
  statement {
    sid    = "ApiAndAuth"
    effect = "Allow"
    actions = [
      "apigateway:*",
      "cognito-idp:*",
      "wafv2:*"
    ]
    resources = ["*"]
  }

  # Orchestration événementielle
  # "rag-*" : la regle EventBridge (rag-document-uploaded-*) et la file SQS DLQ
  # (rag-ingestion-dlq-*) ne suivent pas non plus la convention "rag-platform-*".
  statement {
    sid     = "Events"
    effect  = "Allow"
    actions = ["events:*", "sqs:*", "states:*"]
    resources = [
      "arn:aws:events:*:*:rule/rag-*",
      "arn:aws:sqs:*:*:rag-*",
      "arn:aws:states:*:*:stateMachine:rag-*"
    ]
  }

  # Chiffrement
  statement {
    sid       = "Encryption"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"] # les clés n'existent pas encore au premier apply, donc pas d'ARN à scoper a priori
  }

  # Observabilité
  statement {
    sid       = "Observability"
    effect    = "Allow"
    actions   = ["logs:*", "cloudtrail:*"]
    resources = ["*"]
  }

  # IAM — la partie sensible, très encadrée (voir permissions boundary ci-dessous)
  # "rag-*" : les roles applicatifs (rag-orchestrator-lambda-*, rag-ingestion-lambda-*,
  # rag-vpc-flow-logs-*, rag-api-gateway-cloudwatch-*) ne suivent pas non plus
  # "rag-platform-*".
  statement {
    sid    = "IAMScoped"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:TagRole", "iam:PassRole"
    ]
    resources = ["arn:aws:iam::*:role/rag-*"]
    condition {
      # Verrou structurel : impossible de créer/modifier un rôle SANS lui attacher
      # la permissions boundary définie plus bas - même si l'action est autorisée ci-dessus
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.permissions_boundary.arn]
    }
  }

  statement {
    sid    = "DenyBoundaryTampering"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary",
      "iam:PutRolePermissionsBoundary"
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.permissions_boundary.arn]
    }
  }
}