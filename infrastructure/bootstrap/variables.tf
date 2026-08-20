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
  default = "RAG-entreprise" # nom reel du repo GitHub - "rag-platform" n'etait que le nom
  # de projet initial, jamais celui du repo (utilise a tort ici, cassait sts:AssumeRoleWithWebIdentity)
}