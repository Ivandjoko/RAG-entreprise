# environments/dev/main.tf
module "networking" {
  source             = "../../modules/networking"
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  log_retention_days = var.retention_days
  kms_audit_key_arn  = module.security.kms_audit_key_arn
}

module "security" {
  source             = "../../modules/security"
  environment        = var.environment
  guardrail_strength = var.guardrail_strength
  aws_region         = var.aws_region
  # documents_bucket_arn / metadata_table_arn ne sont plus des inputs de ce module : les
  # grants IAM correspondants sont accordés depuis modules/ingestion, qui possède ces
  # ressources (voir modules/ingestion/iam_grants.tf, même logique que le grant aoss).
}

module "ingestion" {
  source                         = "../../modules/ingestion"
  environment                    = var.environment
  private_subnet_ids             = module.networking.private_subnet_ids
  lambda_security_group_id       = module.networking.lambda_security_group_id
  kms_data_key_arn               = module.security.kms_data_key_arn
  kms_audit_key_arn              = module.security.kms_audit_key_arn
  ingestion_lambda_role_arn      = module.security.ingestion_lambda_role_arn
  opensearch_collection_endpoint = module.retrieval.collection_endpoint
  opensearch_index_name          = module.retrieval.index_name
  log_retention_days             = var.retention_days
}

module "retrieval" {
  source                          = "../../modules/retrieval"
  environment                     = var.environment
  vpc_id                          = module.networking.vpc_id
  private_subnet_ids              = module.networking.private_subnet_ids
  lambda_security_group_id        = module.networking.lambda_security_group_id
  vpc_endpoints_security_group_id = module.networking.vpc_endpoints_security_group_id
  kms_data_key_arn                = module.security.kms_data_key_arn
  kms_audit_key_arn               = module.security.kms_audit_key_arn
  ingestion_lambda_role_arn       = module.security.ingestion_lambda_role_arn
  orchestrator_lambda_role_arn    = module.security.orchestrator_lambda_role_arn
  guardrail_id                    = module.security.guardrail_id
  guardrail_version               = module.security.guardrail_version
  log_retention_days              = var.retention_days
  collection_name                 = "rag-vectors-${var.environment}"
  index_name                      = "rag-index-${var.environment}"
}

module "api" {
  source                            = "../../modules/api"
  environment                       = var.environment
  orchestrator_lambda_invoke_arn    = module.retrieval.orchestrator_lambda_invoke_arn
  orchestrator_lambda_function_name = module.retrieval.orchestrator_lambda_function_name
  kms_audit_key_arn                 = module.security.kms_audit_key_arn
  permission_groups                 = ["public", "finance-team", "hr-confidential"]
  throttling_rate_limit             = 20
  throttling_burst_limit            = 40
  waf_rate_limit_per_ip             = 500
  blocked_countries                 = []
  log_retention_days                = var.retention_days
  enable_waf                        = true
}

provider "aws" {
  region = var.aws_region
  # Pas de "profile" ici : Terraform utilise automatiquement
  # AWS_PROFILE (local) ou les credentials OIDC injectées (CI)
}
