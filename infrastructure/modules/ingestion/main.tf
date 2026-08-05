# modules/ingestion/main.tf

# Zip du code source uniquement (pas les .tf, pas le state) : les dépendances tierces
# (pypdf, python-docx, beautifulsoup4, opensearch-py) ne sont PAS incluses ici et
# nécessitent une étape de build séparée (Lambda layer ou pip install -t avant packaging),
# voir le rapport d'audit.
data "archive_file" "ingestion" {
  type        = "zip"
  output_path = "${path.module}/build/ingestion.zip"

  source {
    content  = file("${path.module}/handler.py")
    filename = "handler.py"
  }
  source {
    content  = file("${path.module}/chunking.py")
    filename = "chunking.py"
  }
  source {
    content  = file("${path.module}/embeddings.py")
    filename = "embeddings.py"
  }
  source {
    content  = file("${path.module}/indexer.py")
    filename = "indexer.py"
  }
  source {
    content  = file("${path.module}/metadata_store.py")
    filename = "metadata_store.py"
  }
  source {
    content  = file("${path.module}/parsers.py")
    filename = "parsers.py"
  }
  source {
    content  = file("${path.module}/opensearch_client.py")
    filename = "opensearch_client.py"
  }
}

resource "aws_lambda_function" "ingestion" {
  function_name    = "rag-ingestion-${var.environment}"
  role              = var.ingestion_lambda_role_arn
  handler           = "handler.handler"
  runtime           = "python3.12"
  timeout           = 120
  memory_size       = 512
  filename          = data.archive_file.ingestion.output_path
  source_code_hash  = data.archive_file.ingestion.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      OPENSEARCH_INDEX_NAME          = var.opensearch_index_name
      OPENSEARCH_COLLECTION_ENDPOINT = var.opensearch_collection_endpoint
      METADATA_TABLE_NAME            = var.metadata_table_name
      # AWS_REGION n'est PAS défini ici : c'est une clé réservée que Lambda injecte
      # automatiquement (Terraform rejette toute tentative de la définir soi-même).
      # handler.py lit os.environ["AWS_REGION"], déjà fourni par le runtime.
    }
  }
}

# Sans cette permission, la règle EventBridge ne peut pas invoquer la Lambda (AccessDenied silencieux)
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.document_uploaded.arn
}
