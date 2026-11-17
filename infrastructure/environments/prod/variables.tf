# environments/prod/variables.tf
variable "environment" {
  type    = string
  default = "prod"
}

variable "vpc_cidr" {
  type = string
}

variable "guardrail_strength" {
  type = string
}

variable "retention_days" {
  type = number
}

variable "aws_region" {
  type    = string
  default = "eu-west-3"
}
