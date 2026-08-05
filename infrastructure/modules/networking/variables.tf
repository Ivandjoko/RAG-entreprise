# modules/networking/variables.tf
variable "environment" {
  type        = string
  description = "dev, staging ou prod"
}
variable "vpc_cidr" {
  type = string
}
variable "azs" {
  type    = list(string)
  default = ["eu-west-3a", "eu-west-3b"]
}