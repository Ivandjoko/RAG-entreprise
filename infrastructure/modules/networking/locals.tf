# modules/networking/locals.tf (répété dans chaque module ou factorisé)
locals {
  common_tags = {
    Project     = "rag-platform"
    Environment = var.environment
    ManagedBy   = "terraform"
    CostCenter  = "ai-innovation"
  }
}