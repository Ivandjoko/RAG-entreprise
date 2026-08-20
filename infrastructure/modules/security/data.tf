# modules/security/data.tf
data "aws_caller_identity" "current" {}

# Resolue par nom plutot que passee en variable : cette policy vit dans le state du
# bootstrap (un root Terraform totalement separe), pas dans celui-ci. Requise sur tout role
# rag-* pour satisfaire la condition iam:PermissionsBoundary imposee par la policy
# terraform_deployer du role CI (voir infrastructure/bootstrap/policies).
data "aws_iam_policy" "permissions_boundary" {
  name = "rag-platform-permissions-boundary"
}
