# modules/api/account_settings.tf
# Réglage au niveau du COMPTE (pas du stage) : API Gateway refuse d'activer les access logs
# sur un stage tant qu'un rôle CloudWatch n'est pas configuré ici. Un seul de ces réglages
# existe par compte+région - comme dev/staging/prod sont 3 comptes AWS séparés, pas de conflit.

# Resolue par nom plutot que passee en variable : cette policy vit dans le state du bootstrap
# (root Terraform separe), pas dans celui-ci. Requise sur tout role rag-* pour satisfaire la
# condition iam:PermissionsBoundary de la policy terraform_deployer du CI.
data "aws_iam_policy" "permissions_boundary" {
  name = "rag-platform-permissions-boundary"
}

resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "rag-api-gateway-cloudwatch-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}
