# modules/retrieval/versions.tf
# Pas de bloc "provider" ici : ce module hérite de la configuration provider de
# l'environnement (dev/staging/prod) qui l'appelle.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}
