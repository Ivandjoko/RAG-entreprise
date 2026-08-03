# modules/security/kms_policy.tf
data "aws_iam_policy_document" "kms_data_policy" {
  # Bloc 1 : les admins du compte gardent le contrôle total de la clé (rotation, suppression...)
  statement {
    sid    = "AllowKeyAdministration"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Bloc 2 : seuls les rôles applicatifs désignés peuvent chiffrer/déchiffrer - PAS gérer la clé
  statement {
    sid    = "AllowLambdaUsage"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = var.authorized_role_arns  # rempli plus bas avec les rôles Lambda
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = ["*"]
  }
}