# modules/security/guardrails.tf

resource "aws_bedrock_guardrail" "main" {
  name                      = "rag-guardrail-${var.environment}"
  description               = "Garde-fou de contenu pour le RAG - ${var.environment}"
  blocked_input_messaging   = "Votre question contient du contenu qui ne peut pas être traité."
  blocked_outputs_messaging = "Je ne peux pas fournir cette réponse pour des raisons de sécurité."

  # 1. Filtre de contenu : bloque violence, haine, contenu sexuel, etc.
  #    en entrée ET en sortie, avec un niveau de sévérité paramétrable
  content_policy_config {
    filters_config {
      type            = "HATE"
      input_strength  = var.guardrail_strength   # LOW / MEDIUM / HIGH selon l'environnement
      output_strength = var.guardrail_strength
    }
    filters_config {
      type            = "PROMPT_ATTACK"           # ← le filtre anti prompt-injection
      input_strength  = "HIGH"                    # toujours HIGH ici, non négociable
      output_strength = "NONE"                     # n'a pas de sens en sortie
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = var.guardrail_strength
      output_strength = var.guardrail_strength
    }
  }

  # 2. Détection et masquage des données personnelles (PII)
  #    ANONYMIZE remplace la donnée par un tag, BLOCK bloque la réponse entière
  sensitive_information_policy_config {
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "US_SOCIAL_SECURITY_NUMBER"  # à adapter : NIR pour la France si besoin via regex custom
      action = "BLOCK"
    }
  }

  # 3. Sujets explicitement interdits, propres au métier du client
  #    Exemple : un client bancaire qui ne veut jamais que le RAG donne un conseil d'investissement
  topic_policy_config {
    topics_config {
      name       = "conseil-financier"
      definition = "Toute recommandation d'investissement ou conseil financier personnalisé"
      examples   = ["Devrais-je investir dans cette action ?"]
      type       = "DENY"
    }
  }

  # 4. Ancrage : force le modèle à ne répondre qu'à partir du contexte récupéré (anti-hallucination)
  contextual_grounding_policy_config {
    filters_config {
      type      = "GROUNDING"
      threshold = 0.75   # si la réponse n'est pas suffisamment ancrée dans les documents, elle est bloquée
    }
    filters_config {
      type      = "RELEVANCE"
      threshold = 0.7    # bloque les réponses hors-sujet par rapport à la question posée
    }
  }

  kms_key_arn = aws_kms_key.data.arn
}

resource "aws_bedrock_guardrail_version" "main" {
  guardrail_arn = aws_bedrock_guardrail.main.guardrail_arn
  description   = "Version stable pour ${var.environment}"
}