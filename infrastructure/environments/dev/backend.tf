# environments/dev/backend.tf
terraform {
  backend "s3" {
    bucket         = "acme-rag-tfstate-dev"
    key            = "rag-platform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "acme-rag-tfstate-lock-dev"
    encrypt        = true
  }
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}