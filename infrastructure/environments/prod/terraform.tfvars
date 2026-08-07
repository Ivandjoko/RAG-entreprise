# environments/prod/terraform.tfvars
environment       = "prod"
vpc_cidr          = "10.30.0.0/16"
retention_days    = 90
guardrail_strength = "HIGH"