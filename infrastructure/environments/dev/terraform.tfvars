# environments/dev/terraform.tfvars
environment        = "dev"
vpc_cidr           = "10.10.0.0/16"
retention_days     = 7
guardrail_strength = "MEDIUM"