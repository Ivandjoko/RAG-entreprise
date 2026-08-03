# modules/networking/main.tf
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