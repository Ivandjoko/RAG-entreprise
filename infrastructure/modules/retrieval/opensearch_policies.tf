# modules/retrieval/opensearch_policies.tf

# Policy de chiffrement : impose l'utilisation de TA clé KMS, pas la clé AWS par défaut
resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "rag-encryption-${var.environment}"
  type = "encryption"
  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${var.collection_name}"]
      }
    ]
    AWSOwnedKey = false                # false = on force notre propre clé KMS
    KmsARN      = var.kms_data_key_arn # vient du module security
  })
}

# Policy réseau : interdit tout accès public, uniquement depuis le VPC via l'endpoint
resource "aws_opensearchserverless_security_policy" "network" {
  name = "rag-network-${var.environment}"
  type = "network"
  policy = jsonencode([
    {
      Rules = [
        { ResourceType = "collection", Resource = ["collection/${var.collection_name}"] },
        { ResourceType = "dashboard",  Resource = ["collection/${var.collection_name}"] }
      ]
      AllowFromPublic = false
      SourceVPCEs     = [var.opensearch_vpc_endpoint_id]
    }
  ])
}