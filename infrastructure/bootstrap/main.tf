# infrastructure/bootstrap/main.tf

terraform {
  required_version = ">= 1.9"
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
# Logging d'acces S3 necessiterait un bucket de logs dedie supplementaire - le CloudTrail
# deja actif au niveau compte couvre l'audit des API calls S3 (GetObject/PutObject) sur ce
# bucket, sans infra additionnelle a maintenir ici (meme raisonnement que le skip checkov
# CKV_AWS_18 ci-dessous).
# tfsec:ignore:aws-s3-enable-bucket-logging
resource "aws_s3_bucket" "tfstate" {
  bucket = "acme-rag-tfstate-${var.environment_suffix}"

  # checkov:skip=CKV_AWS_144: replication cross-region disproportionnee pour un bucket de
  # state Terraform en dev/staging/prod - le versioning + la sauvegarde locale par compte
  # (terraform.{env}.tfstate) couvrent deja le risque de perte accidentelle.
  # checkov:skip=CKV_AWS_18: logging d'acces S3 necessiterait un bucket de logs dedie
  # supplementaire - le CloudTrail deja actif au niveau compte couvre l'audit des API calls
  # S3 (GetObject/PutObject) sur ce bucket, sans infra additionnelle a maintenir ici.
  # checkov:skip=CKV2_AWS_62: bucket de state Terraform, aucun consommateur d'evenements
  # (pas de pipeline de traitement a declencher sur upload de state).
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

# CMK dediee disproportionnee pour un bucket de state Terraform du bootstrap - "aws:kms"
# (cle AWS-managed) chiffre deja au repos ; meme raisonnement que le skip DynamoDB juste
# au-dessus (pas de donnee sensible propre au bucket, deja protege par ailleurs - IAM,
# versioning, PAB).
# tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Pas de suppression de versions ici (contrairement au bucket documents) : un ancien state
# Terraform doit rester récupérable indéfiniment en cas d'incident - seule règle utile pour
# un bucket de state : nettoyer les uploads multipart interrompus, jamais visibles autrement.
# checkov:skip=CKV2_AWS_61: ce check exige une regle d'EXPIRATION en plus - volontairement
# absente ici, un state Terraform ne doit pas expirer automatiquement.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
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

  # Une table de verrous Terraform n'a pas de donnee a "recuperer" (juste un lock ID
  # ephemere), mais l'activer coute rien en PAY_PER_REQUEST et satisfait CKV_AWS_28.
  point_in_time_recovery {
    enabled = true
  }

  # Chiffrement explicite (cle AWS-owned, gratuite) : sans ce bloc, certains scanners
  # (tfsec) signalent l'absence de config meme si DynamoDB chiffre deja tout au repos par
  # defaut depuis 2018 - l'expliciter coute rien et satisfait le check. CMK dediee non
  # utilisee : disproportionnee pour une table de lock ephemere sans donnee sensible (meme
  # raisonnement que le skip checkov CKV_AWS_119).
  # tfsec:ignore:aws-dynamodb-table-customer-key
  server_side_encryption {
    enabled = true
  }

  # checkov:skip=CKV_AWS_119: table de lock Terraform (aucune donnee sensible, juste un
  # LockID ephemere) - chiffrement AWS-owned deja actif par defaut ; une CMK dediee au seul
  # bootstrap serait disproportionnee pour cette table.
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