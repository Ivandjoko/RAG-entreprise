# infrastructure/bootstrap/variables.tf
variable "environment_suffix" {
  type    = string
  default = "shared"
}
variable "github_org" {
  type = string
}
variable "github_repo" {
  type    = string
  default = "rag-platform"
}