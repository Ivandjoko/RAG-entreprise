# infrastructure/bootstrap/policies/permissions_boundary.tf

data "aws_iam_policy_document" "permissions_boundary" {
  statement {
    sid    = "AllowProjectServices"
    effect = "Allow"
    actions = [
      "s3:*", "dynamodb:*", "lambda:*", "bedrock:*", "aoss:*",
      "apigateway:*", "cognito-idp:*", "wafv2:*",
      "events:*", "sqs:*", "states:*", "kms:*", "logs:*",
      "ec2:Describe*", "ec2:*Vpc*", "ec2:*Subnet*", "ec2:*SecurityGroup*", "ec2:*VpcEndpoint*",
      # Oublie lors du premier passage de cette boundary : creer une VPC (ou tout autre
      # ressource EC2 avec un bloc "tags") appelle implicitement ec2:CreateTags - sans cette
      # action, meme une identity policy qui autorise ec2:*Vpc* se fait bloquer par la
      # boundary (erreur "no permissions boundary allows the ec2:CreateTags action").
      "ec2:*Tags*",
      # Table de routage privee (modules/networking) - aucun des patterns ci-dessus ne
      # couvre "RouteTable".
      "ec2:*RouteTable*",
      # aws_opensearchserverless_vpc_endpoint gere en interne des hosted zones Route53
      # privees (meme mecanique que les VPC interface endpoints standard) - sans ces
      # actions, la creation de l'endpoint AOSS reste bloquee en FAILED indefiniment.
      "route53:*"
    ]
    resources = ["*"]
  }

  # Gestion des roles IAM applicatifs (Lambda, VPC flow logs, API Gateway CloudWatch...) crees
  # par Terraform - scope volontairement plus etroit que le reste (role/rag-* uniquement),
  # jamais "*", meme si le reste de cette boundary est deja tres large.
  statement {
    sid    = "AllowProjectIAMRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:TagRole", "iam:PassRole"
    ]
    resources = ["arn:aws:iam::*:role/rag-*"]
  }

  # Necessaire pour que les modules applicatifs (security/networking/api) puissent resoudre
  # l'ARN de cette boundary via `data "aws_iam_policy"` et l'attacher a leurs propres roles -
  # condition requise par terraform_deployer.IAMScoped pour tout iam:CreateRole sur role/rag-*.
  statement {
    sid       = "AllowReadOwnBoundaryPolicy"
    effect    = "Allow"
    actions   = ["iam:GetPolicy"]
    resources = ["arn:aws:iam::*:policy/rag-platform-permissions-boundary"]
  }

  # Le verrou principal : même un rôle créé par Terraform ne peut JAMAIS
  # faire d'action IAM destructrice/élévatrice, quelle que soit sa policy attachée
  statement {
    sid    = "DenyPrivilegeEscalation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreatePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:AttachUserPolicy",
      "iam:PutUserPolicy",
      "organizations:*", # aucun rôle applicatif n'a besoin de toucher Organizations
      "account:*"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyBoundaryRemoval"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "permissions_boundary" {
  name   = "rag-platform-permissions-boundary"
  policy = data.aws_iam_policy_document.permissions_boundary.json
}