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

  # aws_opensearchserverless_vpc_endpoint gere en interne des hosted zones Route53 privees
  # (meme mecanique que les VPC interface endpoints standard) - sans ca, l'endpoint reste
  # bloque en FAILED indefiniment. Deja couvert par PowerUserAccess aujourd'hui (encore
  # attache au role CI), mais ajoute ici pour que ce policy scope reste autosuffisant une
  # fois PowerUserAccess retire (voir memoire projet).
  statement {
    sid       = "Route53ForVpcEndpoints"
    effect    = "Allow"
    actions   = ["route53:*"]
    resources = ["*"]
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
  #
  # Seul iam:CreateRole porte reellement la cle de condition "iam:PermissionsBoundary"
  # dans le contexte de la requete (c'est l'appel qui specifie quelle boundary attacher).
  # Regrouper GetRole/ListRolePolicies/PutRolePolicy/etc. dans CE MEME statement avec CETTE
  # condition les rendait silencieusement inutilisables : sans la cle dans leur contexte,
  # StringEquals evalue a faux et le Allow ne s'applique jamais - quel que soit le temps
  # d'attente. D'ou la separation en deux statements.
  statement {
    sid       = "IAMCreateRoleScoped"
    effect    = "Allow"
    actions   = ["iam:CreateRole"]
    resources = ["arn:aws:iam::*:role/rag-*"]
    condition {
      # Verrou structurel : impossible de créer un rôle SANS lui attacher
      # la permissions boundary définie plus bas - même si l'action est autorisée ci-dessus
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.permissions_boundary.arn]
    }
  }

  statement {
    sid    = "IAMRoleLifecycleScoped"
    effect = "Allow"
    actions = [
      "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:TagRole", "iam:PassRole", "iam:ListRolePolicies"
    ]
    resources = ["arn:aws:iam::*:role/rag-*"]
  }

  # Necessaire pour que les modules applicatifs (security/networking/api) puissent resoudre
  # l'ARN de la boundary via `data "aws_iam_policy"` avant de l'attacher a leurs propres roles.
  statement {
    sid    = "AllowReadOwnBoundaryPolicy"
    effect = "Allow"
    # GetPolicyVersion est necessaire en plus de GetPolicy : data "aws_iam_policy" lit
    # aussi le document de la version par defaut, pas seulement les metadonnees.
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = [aws_iam_policy.permissions_boundary.arn]
  }

  # `data "aws_iam_policy"` (recherche par nom) appelle iam:ListPolicies en interne avant
  # iam:GetPolicy - cette action ne supporte pas le scoping par ARN (liste tout le compte).
  statement {
    sid       = "AllowListPoliciesForBoundaryLookup"
    effect    = "Allow"
    actions   = ["iam:ListPolicies"]
    resources = ["*"]
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