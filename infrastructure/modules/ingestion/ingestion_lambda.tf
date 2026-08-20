# modules/ingestion/ingestion_lambda.tf

data "archive_file" "ingestion_code" {
  type        = "zip"
  source_dir  = "${path.module}/../../../src/ingestion_lambda"
  output_path = "${path.module}/build/ingestion_code.zip"
}

resource "aws_lambda_layer_version" "ingestion_deps" {
  layer_name          = "rag-ingestion-deps-${var.environment}"
  filename            = "${path.module}/build/ingestion_layer.zip"
  compatible_runtimes = ["python3.12"]
  source_code_hash    = filebase64sha256("${path.module}/build/ingestion_layer.zip")
  # contient : opensearch-py, pypdf, python-docx, beautifulsoup4
}

resource "aws_lambda_function" "ingestion" {
  function_name = "rag-ingestion-${var.environment}"
  role          = var.ingestion_lambda_role_arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 300  # jusqu'à 5 min : Textract sur un gros PDF scanné peut être lent
  memory_size   = 1024 # plus élevé que l'orchestrateur : parsing PDF/DOCX consomme plus de mémoire

  filename         = data.archive_file.ingestion_code.output_path
  source_code_hash = data.archive_file.ingestion_code.output_base64sha256
  layers           = [aws_lambda_layer_version.ingestion_deps.arn]

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  kms_key_arn = var.kms_data_key_arn

  environment {
    variables = {
      OPENSEARCH_COLLECTION_ENDPOINT = var.opensearch_collection_endpoint
      OPENSEARCH_INDEX_NAME          = var.opensearch_index_name
      METADATA_TABLE_NAME            = aws_dynamodb_table.metadata.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  # Pas de reserved_concurrent_executions ici : le quota de concurrence Lambda de ce compte
  # est trop bas pour réserver quoi que ce soit sans faire passer le pool non-réservé sous
  # le minimum AWS de 10. À réactiver une fois un relèvement de quota demandé (voir
  # var.ingestion_max_concurrency, toujours déclarée mais non câblée pour l'instant).
}

resource "aws_cloudwatch_log_group" "ingestion" {
  name              = "/aws/lambda/rag-ingestion-${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_audit_key_arn
}