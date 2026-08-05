# infrastructure/bootstrap/policies/versions.tf
# Pas de bloc "provider" ici : ce module est appelé comme sous-module de bootstrap/,
# qui lui fournit sa configuration provider par héritage implicite.
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}
