# modules/networking/main.tf
data "aws_region" "current" {}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.common_tags, { Name = "rag-vpc-${var.environment}" })
}

resource "aws_subnet" "private" {
  for_each          = toset(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, index(var.azs, each.value))
  availability_zone = each.value
  tags = merge(local.common_tags, { Name = "rag-private-${each.value}" })
}

# Table de routage privée, associée à chaque subnet privé (pas de route publique :
# tout le trafic externe passe par les VPC endpoints ci-dessous)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "rag-private-rt-${var.environment}" })
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# Security group des VPC endpoints Interface, et security group des Lambdas : ils se
# référencent mutuellement (Lambda -> egress vers vpc_endpoints, vpc_endpoints <- ingress
# depuis Lambda). Les règles sont donc déclarées à part (aws_vpc_security_group_*_rule),
# jamais inline dans les 2 resources aws_security_group elles-mêmes, sinon Terraform détecte
# un cycle de dépendance (chacun aurait besoin de l'ID de l'autre pour être créé).
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "rag-vpc-endpoints-${var.environment}-"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "rag-vpc-endpoints-${var.environment}" })
}

resource "aws_security_group" "lambda" {
  name_prefix = "rag-lambda-${var.environment}-"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "rag-lambda-${var.environment}" })
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_from_lambda" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  description                  = "HTTPS depuis les Lambdas"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_vpc_endpoints" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "HTTPS sortant vers les VPC endpoints (Bedrock, S3, DynamoDB, OpenSearch Serverless)"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.vpc_endpoints.id
}

# VPC endpoints pour rester privé (pas de NAT Gateway = économie + sécurité)
resource "aws_vpc_endpoint" "bedrock" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.bedrock-runtime"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [for s in aws_subnet.private : s.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}

# modules/networking/main.tf — ajouts

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"   # Gateway comme S3, gratuit, via route table
  route_table_ids   = [aws_route_table.private.id]
}

# Pas d'endpoint OpenSearch Serverless ici : ce n'est PAS un service PrivateLink standard
# (aws_vpc_endpoint), c'est une ressource dédiée (aws_opensearchserverless_vpc_endpoint),
# déjà créée et gérée dans modules/retrieval/vpc_endpoint.tf.