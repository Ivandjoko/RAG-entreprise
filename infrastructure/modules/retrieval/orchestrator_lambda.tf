# modules/retrieval/orchestrator_lambda.tf
# Le code source vit dans src/query_orchestrator_lambda/ (hors de ce module) : c'est le
# layout retenu pour cette Lambda, à la différence de l'ingestion dont le code vit dans
# infrastructure/modules/ingestion/. Packaging du code source uniquement (pas les
# dépendances tierces opensearch-py/boto3 au-delà du runtime - build layer à ajouter).
locals {
  orchestrator_src = "${path.module}/../../../src/query_orchestrator_lambda"
}

# source_dir zippe tout le dossier (y compris requirements.txt, inoffensif) : plus besoin
# de lister chaque fichier .py à la main ni de le maintenir à jour à chaque ajout.
data "archive_file" "orchestrator" {
  type        = "zip"
  source_dir  = local.orchestrator_src
  output_path = "${path.module}/build/orchestrator.zip"
}

resource "aws_lambda_function" "orchestrator" {
  function_name    = "rag-orchestrator-${var.environment}"
  role              = var.orchestrator_lambda_role_arn
  handler           = "handler.handler"
  runtime           = "python3.12"
  # 30s etait trop court : guardrail input + DynamoDB + embed_query + recherche hybride +
  # rerank Cohere + generation Claude + guardrail output + audit log s'enchainent, et
  # depassent 30s des que Bedrock/OpenSearch repondent lentement. Voir aussi le
  # timeout_milliseconds cote aws_api_gateway_integration.query_lambda (api_gateway.tf).
  timeout           = 60
  memory_size       = 1024
  filename          = data.archive_file.orchestrator.output_path
  source_code_hash  = data.archive_file.orchestrator.output_base64sha256
  layers           = [aws_lambda_layer_version.orchestrator_deps.arn]

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }
  kms_key_arn = var.kms_data_key_arn

  environment {
    variables = {
      GUARDRAIL_ID                   = var.guardrail_id
      GUARDRAIL_VERSION              = var.guardrail_version
      OPENSEARCH_COLLECTION_ENDPOINT = aws_opensearchserverless_collection.vectors.collection_endpoint
      OPENSEARCH_INDEX_NAME          = var.index_name
      USER_PERMISSIONS_TABLE_NAME    = aws_dynamodb_table.user_permissions.name
      # AWS_REGION est une clé réservée, injectée automatiquement par Lambda.
    }
  }
  tracing_config {
    mode = "Active"   # X-Ray, cohérent avec xray_tracing_enabled activé côté API Gateway
  }
  depends_on = [aws_opensearchserverless_access_policy.collection_access]

}

resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/aws/lambda/rag-orchestrator-${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_audit_key_arn
}

# Log group applicatif utilise par audit.py (log_query) - distinct du log group ci-dessus
# (stdout de la fonction). iam_orchestrator.tf autorisait deja logs:PutLogEvents dessus,
# mais sans ce resource le log group lui-meme n'existait jamais : CreateLogStream echouait
# avec ResourceNotFoundException a la premiere execution.
resource "aws_cloudwatch_log_group" "query_audit" {
  name              = "/aws/rag-platform/query-audit"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_audit_key_arn
}

resource "aws_lambda_layer_version" "orchestrator_deps" {
  layer_name          = "rag-orchestrator-deps-${var.environment}"
  filename            = "${path.module}/build/orchestrator_layer.zip"
  compatible_runtimes  = ["python3.12"]
  source_code_hash     = filebase64sha256("${path.module}/build/orchestrator_layer.zip")
}