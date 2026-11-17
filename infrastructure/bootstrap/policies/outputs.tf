# infrastructure/bootstrap/policies/outputs.tf
output "terraform_deployer_policy_json" {
  value = data.aws_iam_policy_document.terraform_deployer.json
}

output "permissions_boundary_arn" {
  value = aws_iam_policy.permissions_boundary.arn
}
