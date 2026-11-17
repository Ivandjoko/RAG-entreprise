# infrastructure/environments/staging/backend.tf
terraform {
  backend "s3" {
    bucket         = "acme-rag-tfstate-staging"
    key            = "rag-platform/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "acme-rag-tfstate-lock-staging"
    encrypt        = true
  }
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}