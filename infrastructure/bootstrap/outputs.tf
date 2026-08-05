# infrastructure/bootstrap/outputs.tf
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
output "tfstate_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}
output "terraform_deployer_policy_arn" {
  value = aws_iam_policy.terraform_deployer.arn
}

output "permissions_boundary_arn" {
  value = module.policies.permissions_boundary_arn
}
# infrastructure/bootstrap/outputs.tf

output "terraform_deployer_policy_json" {
  value = data.aws_iam_policy_document.terraform_deployer.json
}