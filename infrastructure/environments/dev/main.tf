# environments/dev/main.tf
module "networking" {
  source      = "../../modules/networking"
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
}

module "security" {
  source             = "../../modules/security"
  environment        = var.environment
  guardrail_strength = var.guardrail_strength
  aws_region         = var.aws_region
  # documents_bucket_arn, metadata_table_arn : pas encore câblables, aucune ressource
  # S3/DynamoDB n'existe encore côté Terraform (voir rapport d'audit). `terraform plan`
  # échouera ici tant qu'elles ne sont pas ajoutées.
}

module "ingestion" {
  source                         = "../../modules/ingestion"
  environment                    = var.environment
  private_subnet_ids             = module.networking.private_subnet_ids
  lambda_security_group_id       = module.networking.lambda_security_group_id
  kms_data_key_arn               = module.security.kms_data_key_arn
  ingestion_lambda_role_arn      = module.security.ingestion_lambda_role_arn
  opensearch_collection_endpoint = module.retrieval.collection_endpoint
  opensearch_index_name          = module.retrieval.index_name
  # documents_bucket_name, metadata_table_name : pas encore câblables, aucune ressource
  # S3/DynamoDB n'existe encore côté Terraform (voir rapport d'audit).
}

module "retrieval" {
  source                           = "../../modules/retrieval"
  environment                      = var.environment
  vpc_id                           = module.networking.vpc_id
  private_subnet_ids               = module.networking.private_subnet_ids
  lambda_security_group_id         = module.networking.lambda_security_group_id
  vpc_endpoints_security_group_id  = module.networking.vpc_endpoints_security_group_id
  kms_data_key_arn                 = module.security.kms_data_key_arn
  ingestion_lambda_role_arn        = module.security.ingestion_lambda_role_arn
  orchestrator_lambda_role_arn     = module.security.orchestrator_lambda_role_arn
  guardrail_id                     = module.security.guardrail_id
  guardrail_version                = module.security.guardrail_version
  opensearch_instance_type         = "OCU"   # Serverless = pas d'instance à dimensionner
  # metadata_table_name : pas encore câblable, aucune table DynamoDB n'existe encore
  # côté Terraform (voir rapport d'audit).
}

module "api" {
  source              = "../../modules/api"
  environment         = var.environment
  orchestrator_lambda_arn = module.retrieval.orchestrator_lambda_arn
  enable_waf          = true
}

provider "aws" {
  region = var.aws_region
  # Pas de "profile" ici : Terraform utilise automatiquement
  # AWS_PROFILE (local) ou les credentials OIDC injectées (CI)
}