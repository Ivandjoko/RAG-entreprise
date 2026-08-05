# environments/dev/variables.tf
variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type = string
}

variable "guardrail_strength" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}
