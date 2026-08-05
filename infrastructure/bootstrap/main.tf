# infrastructure/bootstrap/main.tf

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
  # Pas de backend S3 ici volontairement : ce state est petit et local,
  # tu ne veux pas dépendre d'une infra pas encore créée pour le créer
}

provider "aws" {
  region = "eu-west-3"
}

# 1. Bucket S3 pour les states Terraform des vrais environnements
resource "aws_s3_bucket" "tfstate" {
  bucket = "acme-rag-tfstate-${var.environment_suffix}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
  }
}

# 2. Table DynamoDB de verrouillage
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "acme-rag-tfstate-lock-${var.environment_suffix}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

# 3. Le fournisseur OIDC GitHub
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["227203b5317f3818cab5b5ce596132bf36748c0e"]
}

# 4. Le rôle GitHub Actions de ce compte. Un seul rôle par compte (pas "dev"/"prod" fixes) :
#    dev/staging/prod sont 3 comptes AWS distincts, chacun représente UN SEUL environnement.
#    L'accès est gated sur l'environment GitHub du même nom (protection rules côté GitHub :
#    Settings > Environments > ${var.environment_suffix} > required reviewers si besoin),
#    donc chaque job du workflow doit tourner sous `environment: { name: ${var.environment_suffix} }`.
module "policies" {
  source = "./policies"
}

resource "aws_iam_role" "github_actions" {
  name                 = "github-actions-rag-${var.environment_suffix}"
  permissions_boundary = module.policies.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:environment:${var.environment_suffix}"
        }
      }
    }]
  })
}

# Permissions larges pour bootstrap uniquement (à restreindre ensuite, voir note plus bas)
resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# 5. Garde-fous IAM (permissions boundary + policy scopée du déployeur Terraform),
#    en remplacement progressif du PowerUserAccess large ci-dessus.
resource "aws_iam_policy" "terraform_deployer" {
  name   = "rag-platform-terraform-deployer"
  policy = module.policies.terraform_deployer_policy_json
}

resource "aws_iam_role_policy_attachment" "deployer" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.terraform_deployer.arn
}