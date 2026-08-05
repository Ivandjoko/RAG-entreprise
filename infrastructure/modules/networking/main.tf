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

# Security group des VPC endpoints Interface : n'autorise que le HTTPS depuis le VPC lui-même
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "rag-vpc-endpoints-${var.environment}-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS depuis le VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "rag-vpc-endpoints-${var.environment}" })
}

# Security group des Lambdas (ingestion, orchestrateur) : aucun ingress, uniquement
# de l'egress HTTPS vers les VPC endpoints / OpenSearch Serverless / Bedrock
resource "aws_security_group" "lambda" {
  name_prefix = "rag-lambda-${var.environment}-"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS sortant (VPC endpoints, OpenSearch Serverless)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "rag-lambda-${var.environment}" })
}

# VPC endpoints pour rester privé (pas de NAT Gateway = économie + sécurité)
resource "aws_vpc_endpoint" "bedrock" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.bedrock-runtime"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [for s in aws_subnet.private : s.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}