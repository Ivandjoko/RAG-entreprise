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
      identifiers = [aws_iam_role.ingestion_lambda.arn, aws_iam_role.orchestrator_lambda.arn]
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = ["*"]
  }
}

# Politique de la clé d'audit : mêmes admins, mais l'usage applicatif est délégué au
# service CloudWatch Logs (obligatoire pour chiffrer des log groups avec une CMK),
# pas directement aux rôles Lambda qui n'écrivent jamais eux-mêmes de logs chiffrés.
data "aws_iam_policy_document" "kms_audit_policy" {
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

  statement {
    sid    = "AllowCloudWatchLogsUsage"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}