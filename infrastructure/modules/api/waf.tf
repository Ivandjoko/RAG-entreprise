# modules/api/waf.tf

resource "aws_wafv2_web_acl" "main" {
  count       = var.enable_waf ? 1 : 0
  name        = "rag-platform-waf-${var.environment}"
  description = "Protection WAF pour la plateforme RAG"   # pas d'apostrophe : rejetée par la regex WAFv2
  scope       = "REGIONAL"   # REGIONAL pour API Gateway, CLOUDFRONT si jamais devant CloudFront

  default_action {
    allow {}
  }

  # Règle 1 : jeu de règles managées AWS contre les attaques web courantes
  # (XSS, inclusion de fichiers, payloads malveillants génériques)
  rule {
    name     = "AWS-CommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                 = "CommonRuleSet"
      sampled_requests_enabled    = true
    }
  }

  # Règle 2 : protection spécifique injection SQL
  # (utile même si notre backend n'a pas de base SQL directement exposée -
  # certains payloads SQLi ciblent aussi des couches indirectes ou futures évolutions)
  rule {
    name     = "AWS-SQLiRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                 = "SQLiRuleSet"
      sampled_requests_enabled    = true
    }
  }

  # Règle 3 : rate limiting par IP - complète le throttling API Gateway
  # avec une granularité par source, utile contre un abus ciblé
  rule {
    name     = "RateLimitPerIP"
    priority = 3
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit_per_ip  # ex: 500 requêtes / 5 min / IP
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                 = "RateLimitPerIP"
      sampled_requests_enabled    = true
    }
  }

  # Règle 4 : blocage géographique - à activer seulement si le client a un périmètre
  # géographique défini (ex: entreprise française sans besoin d'accès international)
  dynamic "rule" {
    for_each = length(var.blocked_countries) > 0 ? [1] : []
    content {
      name     = "GeoBlock"
      priority = 4
      action {
        block {}
      }
      statement {
        geo_match_statement {
          country_codes = var.blocked_countries
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                 = "GeoBlock"
        sampled_requests_enabled    = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                 = "rag-platform-waf-${var.environment}"
    sampled_requests_enabled    = true
  }

  tags = local.common_tags
}

resource "aws_wafv2_web_acl_association" "api" {
  count        = var.enable_waf ? 1 : 0
  resource_arn = aws_api_gateway_stage.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main[0].arn
}