# modules/api/cognito.tf

resource "aws_cognito_user_pool" "main" {
  name = "rag-platform-users-${var.environment}"

  password_policy {
    minimum_length    = 12
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  # MFA obligatoire en prod, optionnelle ailleurs pour ne pas ralentir le dev
  mfa_configuration = var.environment == "prod" ? "ON" : "OPTIONAL"
  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Empêche l'énumération de comptes : un attaquant ne peut pas savoir
  # si un email existe déjà à partir des messages d'erreur
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  tags = local.common_tags
}

resource "aws_cognito_user_pool_client" "orchestrator" {
  name         = "rag-orchestrator-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id

  # Pas de secret client : c'est une SPA/app publique, le secret ne pourrait
  # pas être protégé côté navigateur de toute façon
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH", # authentification par mot de passe, sécurisée (SRP)
    "ALLOW_REFRESH_TOKEN_AUTH",
    # Nécessite déjà des credentials IAM AWS pour être appelé (admin-initiate-auth) : pas
    # exposé aux utilisateurs finaux via l'app publique, utile pour les tests/ops en CLI.
    "ALLOW_ADMIN_USER_PASSWORD_AUTH"
  ]

  access_token_validity  = 1 # heures - court, pour limiter la fenêtre d'exploitation d'un token volé
  id_token_validity      = 1
  refresh_token_validity = 30 # jours

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED" # même raison que allow_admin_create_user_only ci-dessus
}

# Groupes Cognito : c'est ici que se distinguent les niveaux de permission
# métier (finance-team, hr-confidential...) référencés dans le module retrieval
resource "aws_cognito_user_group" "groups" {
  for_each     = toset(var.permission_groups) # ex: ["public", "finance-team", "hr-confidential"]
  name         = each.value
  user_pool_id = aws_cognito_user_pool.main.id
}