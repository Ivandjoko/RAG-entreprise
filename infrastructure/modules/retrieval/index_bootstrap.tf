# modules/retrieval/index_bootstrap.tf

resource "aws_lambda_function" "index_bootstrap" {
  function_name = "rag-index-bootstrap-${var.environment}"
  # Le rôle orchestrateur n'a qu'un accès en lecture (DescribeIndex/ReadDocument) sur la
  # policy d'accès OpenSearch (voir opensearch_access_policy.tf) - seul le rôle ingestion a
  # CreateIndex/UpdateIndex/WriteDocument, nécessaires pour créer l'index ici.
  role          = var.ingestion_lambda_role_arn
  handler       = "bootstrap.handler"
  runtime       = "python3.12"
  filename      = data.archive_file.index_bootstrap.output_path
  timeout       = 60
  # Réutilise le layer de dépendances de l'orchestrateur (contient déjà opensearch-py) :
  # pas besoin d'un 3e layer/job de build pour cette Lambda de bootstrap ponctuelle.
  layers = [aws_lambda_layer_version.orchestrator_deps.arn]
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }
}

data "archive_file" "index_bootstrap" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_src/index_bootstrap"
  output_path = "${path.module}/build/index_bootstrap.zip"
}

# Invocation Terraform-native : ne s'exécute que si le code ou la config change (idempotent)
resource "aws_lambda_invocation" "create_index" {
  function_name = aws_lambda_function.index_bootstrap.function_name
  input = jsonencode({
    collection_endpoint = aws_opensearchserverless_collection.vectors.collection_endpoint
    index_name           = var.index_name
    mapping_file          = "mapping.json"   # embarqué dans le zip de la Lambda
  })

  # Il faut attendre à la fois la policy d'accès OpenSearch (data-plane) ET le grant IAM
  # AWS (control-plane, aoss:APIAccessAll dans iam_grants.tf) - ce sont deux mécanismes
  # de permission distincts sur ce même rôle. Sans les deux dans le depends_on, Terraform
  # peut invoquer cette Lambda avant que le grant IAM ne soit réellement attaché -> 403.
  depends_on = [
    aws_opensearchserverless_access_policy.collection_access,
    aws_iam_role_policy.ingestion_write_vector_index
  ]
}