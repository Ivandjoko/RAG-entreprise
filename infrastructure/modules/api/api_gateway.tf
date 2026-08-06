# modules/api/api_gateway.tf

resource "aws_api_gateway_rest_api" "main" {
  name = "rag-platform-api-${var.environment}"

  endpoint_configuration {
    types = ["REGIONAL"]  # pas EDGE : on garde le trafic dans la région, pas besoin de CloudFront ici
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

resource "aws_api_gateway_method" "query_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.query.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "query_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.query.id
  http_method             = aws_api_gateway_method.query_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"   # proxy intégral : API Gateway transmet la requête brute à Lambda
  uri                     = var.orchestrator_lambda_invoke_arn
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

  # Logs d'accès structurés, essentiels pour l'audit et le debug
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip              = "$context.identity.sourceIp"
      caller          = "$context.identity.cognitoIdentityId"
      status          = "$context.status"
      latency         = "$context.responseLatency"
      integrationError = "$context.integration.error"
    })
  }

  xray_tracing_enabled = true   # traçabilité de bout en bout, utile pour débugger la latence
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
    throttling_rate_limit  = var.throttling_rate_limit   # ex: 50 req/s en prod
    throttling_burst_limit = var.throttling_burst_limit  # ex: 100
    metrics_enabled         = true
    logging_level            = "INFO"
  }
}