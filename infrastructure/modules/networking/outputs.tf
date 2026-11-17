# modules/networking/outputs.tf
output "vpc_id" {
  value = aws_vpc.main.id
}
output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}
output "lambda_security_group_id" {
  value = aws_security_group.lambda.id
}
output "vpc_endpoints_security_group_id" {
  value = aws_security_group.vpc_endpoints.id
}