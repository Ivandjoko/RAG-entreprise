# infrastructure/bootstrap/variables.tf
variable "environment_suffix" {
  default = "shared"
}
variable "github_org" {
  type = string
}
variable "github_repo" {
  default = "rag-platform"
}