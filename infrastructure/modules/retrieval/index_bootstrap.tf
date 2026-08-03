# modules/retrieval/index_bootstrap.tf

resource "aws_lambda_function" "index_bootstrap" {
  function_name = "rag-index-bootstrap-${var.environment}"
  role          = var.orchestrator_lambda_role_arn  # même rôle suffit ici (lecture/écriture d'index)
  handler       = "bootstrap.handler"
  runtime       = "python3.12"
  filename      = data.archive_file.index_bootstrap.output_path
  timeout       = 60
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

  depends_on = [aws_opensearchserverless_access_policy.collection_access]
}