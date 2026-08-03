# environments/dev/main.tf
module "networking" {
  source      = "../../modules/networking"
  environment = "dev"
  vpc_cidr    = "10.10.0.0/16"
}

module "security" {
  source              = "../../modules/security"
  environment         = "dev"
  vpc_id              = module.networking.vpc_id
}

module "ingestion" {
  source            = "../../modules/ingestion"
  environment       = "dev"
  private_subnet_ids = module.networking.private_subnet_ids
  kms_key_arn       = module.security.kms_key_arn
}

module "retrieval" {
  source              = "../../modules/retrieval"
  environment         = "dev"
  vpc_id              = module.networking.vpc_id
  private_subnet_ids  = module.networking.private_subnet_ids
  opensearch_instance_type = "OCU"   # Serverless = pas d'instance à dimensionner
}

module "api" {
  source              = "../../modules/api"
  environment         = "dev"
  orchestrator_lambda_arn = module.retrieval.orchestrator_lambda_arn
  enable_waf          = true
}