# modules/retrieval/locals.tf
locals {
  common_tags = {
    Project     = "rag-platform"
    Environment = var.environment
    ManagedBy   = "terraform"
    CostCenter  = "ai-innovation"
  }
}
