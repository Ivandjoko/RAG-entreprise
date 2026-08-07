# environments/staging/terraform.tfvars
environment        = "staging"
vpc_cidr           = "10.20.0.0/16"
retention_days     = 30
guardrail_strength = "HIGH"
