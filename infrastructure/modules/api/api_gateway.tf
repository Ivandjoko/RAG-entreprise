# modules/api/api_gateway.tf

resource "aws_api_gateway_rest_api" "main" {
  name = "rag-platform-api-${var.environment}"

  endpoint_configuration {
    types = ["REGIONAL"] # pas EDGE : on garde le trafic dans la région, pas besoin de CloudFront ici
  }
}

resource "aws_api_gateway_authorizer" "cognito" {
  name            = "cognito-authorizer-${var.environment}"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.main.arn]
  identity_source = "method.request.header.Authorization"
}

resource "aws_api_gateway_resource" "query" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "query"
}

resource "aws_api_gateway_request_validator" "query_body" {
  name                        = "validate-query-body"
  rest_api_id                 = aws_api_gateway_rest_api.main.id
  validate_request_body       = true
  validate_request_parameters = false
}

# Rejette un body malformé (pas de "question", mauvais type) directement à la porte
# d'entrée API Gateway - évite un cold start Lambda inutile pour une requête invalide,
# et complète (sans remplacer) la validation déjà faite dans handler.py
resource "aws_api_gateway_model" "query_request" {
  rest_api_id  = aws_api_gateway_rest_api.main.id
  name         = "QueryRequest"
  content_type = "application/json"
  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    type      = "object"
    required  = ["question"]
    properties = {
      question = { type = "string", minLength = 1 }
    }
  })
}

resource "aws_api_gateway_method" "query_post" {
  rest_api_id          = aws_api_gateway_rest_api.main.id
  resource_id          = aws_api_gateway_resource.query.id
  http_method          = "POST"
  authorization        = "COGNITO_USER_POOLS"
  authorizer_id        = aws_api_gateway_authorizer.cognito.id
  request_validator_id = aws_api_gateway_request_validator.query_body.id
  request_models = {
    "application/json" = aws_api_gateway_model.query_request.name
  }
}

resource "aws_api_gateway_integration" "query_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.query.id
  http_method             = aws_api_gateway_method.query_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY" # proxy intégral : API Gateway transmet la requête brute à Lambda
  uri                     = var.orchestrator_lambda_invoke_arn
  # 29000 (defaut/max de base) coupe le client avant que le pipeline RAG complet (guardrail
  # + embed + recherche hybride + rerank + generation LLM) n'ait fini. Necessite une
  # augmentation du quota de compte "Maximum integration timeout in milliseconds"
  # (service apigateway) avant que cette valeur > 29000 soit acceptee par l'API.
  timeout_milliseconds = 60000
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.orchestrator_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  # Scopé à CETTE API précisément, pas à n'importe quelle API Gateway du compte
  source_arn = "${aws_api_gateway_rest_api.main.execution_arn}/*/POST/query"
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    # Force un redéploiement si la config change - sinon API Gateway garde
    # l'ancienne intégration même après un terraform apply réussi
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.query.id,
      aws_api_gateway_method.query_post.id,
      aws_api_gateway_integration.query_lambda.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.environment

  # checkov:skip=CKV2_AWS_51: le mTLS/certificat client sert a verifier que l'appelant parle
  # a un backend HTTP tiers de confiance - integration AWS_PROXY vers Lambda, invocation
  # interne signee AWS de bout en bout, pas de backend HTTP externe a authentifier.
  # checkov:skip=CKV2_AWS_77: la regle AWSManagedRulesKnownBadInputsRuleSet (couvre Log4j)
  # est deja presente dans aws_wafv2_web_acl.main (waf.tf) et associee via
  # aws_wafv2_web_acl_association.api - ce check graphe ne resout pas la reference
  # count-indexee ([0]) a travers l'association, meme quand la regle existe bien.

  # Logs d'accès structurés, essentiels pour l'audit et le debug
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      caller           = "$context.identity.cognitoIdentityId"
      status           = "$context.status"
      latency          = "$context.responseLatency"
      integrationError = "$context.integration.error"
    })
  }

  xray_tracing_enabled = true # traçabilité de bout en bout, utile pour débugger la latence

  # Pas de référence directe vers aws_api_gateway_account.main (réglage de compte, pas
  # rattaché par ARN) : sans ce depends_on explicite, rien ne garantit qu'il soit créé
  # avant que ce stage n'essaie d'activer les access logs.
  depends_on = [aws_api_gateway_account.main]
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/rag-platform-${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_audit_key_arn
}

# Throttling : protège Bedrock et Lambda d'un pic de trafic, et limite les coûts
resource "aws_api_gateway_method_settings" "throttling" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = var.throttling_rate_limit  # ex: 50 req/s en prod
    throttling_burst_limit = var.throttling_burst_limit # ex: 100
    metrics_enabled        = true
    logging_level          = "INFO"
  }
}