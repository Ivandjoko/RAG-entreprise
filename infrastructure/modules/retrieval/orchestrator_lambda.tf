# modules/retrieval/orchestrator_lambda.tf
# Le code source vit dans src/query_orchestrator_lambda/ (hors de ce module) : c'est le
# layout retenu pour cette Lambda, à la différence de l'ingestion dont le code vit dans
# infrastructure/modules/ingestion/. Packaging du code source uniquement (pas les
# dépendances tierces opensearch-py/boto3 au-delà du runtime - build layer à ajouter).
locals {
  orchestrator_src = "${path.module}/../../../src/query_orchestrator_lambda"
}

data "archive_file" "orchestrator" {
  type        = "zip"
  output_path = "${path.module}/build/orchestrator.zip"

  source {
    content  = file("${local.orchestrator_src}/handler.py")
    filename = "handler.py"
  }
  source {
    content  = file("${local.orchestrator_src}/guardrails.py")
    filename = "guardrails.py"
  }
  source {
    content  = file("${local.orchestrator_src}/permissions.py")
    filename = "permissions.py"
  }
  source {
    content  = file("${local.orchestrator_src}/retrieval.py")
    filename = "retrieval.py"
  }
  source {
    content  = file("${local.orchestrator_src}/generation.py")
    filename = "generation.py"
  }
  source {
    content  = file("${local.orchestrator_src}/audit.py")
    filename = "audit.py"
  }
}

resource "aws_lambda_function" "orchestrator" {
  function_name    = "rag-orchestrator-${var.environment}"
  role              = var.orchestrator_lambda_role_arn
  handler           = "handler.handler"
  runtime           = "python3.12"
  timeout           = 30
  memory_size       = 1024
  filename          = data.archive_file.orchestrator.output_path
  source_code_hash  = data.archive_file.orchestrator.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      GUARDRAIL_ID                   = var.guardrail_id
      GUARDRAIL_VERSION              = var.guardrail_version
      OPENSEARCH_COLLECTION_ENDPOINT = aws_opensearchserverless_collection.vectors.collection_endpoint
      OPENSEARCH_INDEX_NAME          = var.index_name
      METADATA_TABLE_NAME            = var.metadata_table_name
      # AWS_REGION est une clé réservée, injectée automatiquement par Lambda.
    }
  }
}
