# infrastructure/bootstrap/policies/permissions_boundary.tf

data "aws_iam_policy_document" "permissions_boundary" {
  statement {
    sid    = "AllowProjectServices"
    effect = "Allow"
    actions = [
      "s3:*", "dynamodb:*", "lambda:*", "bedrock:*", "aoss:*",
      "apigateway:*", "cognito-idp:*", "wafv2:*",
      "events:*", "sqs:*", "states:*", "kms:*", "logs:*",
      "ec2:Describe*", "ec2:*Vpc*", "ec2:*Subnet*", "ec2:*SecurityGroup*", "ec2:*VpcEndpoint*"
    ]
    resources = ["*"]
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