# modules/retrieval/vpc_endpoint.tf
# Endpoint VPC dédié à OpenSearch Serverless (type de ressource distinct des VPC endpoints
# génériques Interface/Gateway créés dans modules/networking) : requis pour que la policy
# réseau "network" ci-dessous puisse restreindre l'accès à la collection au VPC uniquement.
resource "aws_opensearchserverless_vpc_endpoint" "vectors" {
  name               = "rag-aoss-endpoint-${var.environment}"
  vpc_id             = var.vpc_id
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [var.vpc_endpoints_security_group_id]
}
