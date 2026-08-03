terraform {
  backend "s3" {
    bucket         = "REPLACE_ME-terraform-state"
    key            = "rag-platform/terraform.tfstate"
    region         = "REPLACE_ME"
    dynamodb_table = "REPLACE_ME-terraform-locks"
    encrypt        = true
  }
}
