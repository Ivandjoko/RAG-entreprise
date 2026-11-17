# infrastructure/environments/prod/backend.tf
terraform {
  backend "s3" {
    bucket         = "acme-rag-tfstate-prod"
    key            = "rag-platform/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "acme-rag-tfstate-lock-prod"
    encrypt        = true
  }
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}