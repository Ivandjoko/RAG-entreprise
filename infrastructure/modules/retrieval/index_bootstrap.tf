# modules/retrieval/index_bootstrap.tf

resource "aws_lambda_function" "index_bootstrap" {
  function_name = "rag-index-bootstrap-${var.environment}"
  # Le rôle orchestrateur n'a qu'un accès en lecture (DescribeIndex/ReadDocument) sur la
  # policy d'accès OpenSearch (voir opensearch_access_policy.tf) - seul le rôle ingestion a
  # CreateIndex/UpdateIndex/WriteDocument, nécessaires pour créer l'index ici.
  role     = var.ingestion_lambda_role_arn
  handler  = "bootstrap.handler"
  runtime  = "python3.12"
  filename = data.archive_file.index_bootstrap.output_path
  timeout  = 60
  # Réutilise le layer de dépendances de l'orchestrateur (contient déjà opensearch-py) :
  # pas besoin d'un 3e layer/job de build pour cette Lambda de bootstrap ponctuelle.
  layers = [aws_lambda_layer_version.orchestrator_deps.arn]
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }
  tracing_config {
    mode = "Active" # cohérence avec ingestion/orchestrator, coût négligeable pour un run ponctuel
  }
}

data "archive_file" "index_bootstrap" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_src/index_bootstrap"
  output_path = "${path.module}/build/index_bootstrap.zip"
}

# L'ordre de dépendance (depends_on) garantit que Terraform ATTEND que les appels de
# création IAM/OpenSearch aient répondu - mais "a répondu" ne veut pas dire "propagé
# partout". IAM (et, dans une moindre mesure, les access policies OpenSearch Serverless)
# sont en cohérence éventuelle : l'API renvoie 200 avant que la permission ne soit
# effective à 100% côté data-plane. D'où ce délai explicite avant d'invoquer la Lambda.
resource "time_sleep" "wait_for_iam_propagation" {
  depends_on = [
    aws_opensearchserverless_access_policy.collection_access,
    aws_iam_role_policy.ingestion_write_vector_index
  ]
  create_duration = "20s"
}

# Invocation Terraform-native : ne s'exécute que si le code ou la config change (idempotent)
resource "aws_lambda_invocation" "create_index" {
  function_name = aws_lambda_function.index_bootstrap.function_name
  input = jsonencode({
    collection_endpoint = aws_opensearchserverless_collection.vectors.collection_endpoint
    index_name          = var.index_name
    mapping_file        = "mapping.json" # embarqué dans le zip de la Lambda
  })

  depends_on = [time_sleep.wait_for_iam_propagation]
}