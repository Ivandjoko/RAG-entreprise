# guardrails.py
import boto3
from botocore.config import Config

_bedrock_runtime = boto3.client(
    "bedrock-runtime",
    # mode "standard" et non "adaptive" : voir embeddings.py pour le raisonnement (limiteur
    # de debit cote client persistant entre invocations Lambda "warm").
    config=Config(
        connect_timeout=10,
        read_timeout=15,
        retries={"max_attempts": 2, "mode": "standard"},
    ),
)


class ContentBlockedException(Exception):
    """Levée quand le Guardrail bloque le contenu - jamais silencieusement ignorée."""


def _is_hard_block(response: dict) -> bool:
    """
    action == "GUARDRAIL_INTERVENED" est renvoyé aussi bien pour un blocage dur (topic,
    contenu, mot interdit) que pour une simple anonymisation de PII (le texte, déjà masqué
    par le Guardrail, reste utilisable) - il faut inspecter le détail par politique pour
    distinguer les deux cas, sinon toute anonymisation devient un blocage inutile.
    """
    for assessment in response.get("assessments", []):
        if (
            assessment.get("topicPolicy")
            or assessment.get("contentPolicy")
            or assessment.get("wordPolicy")
        ):
            return True
        pii_policy = assessment.get("sensitiveInformationPolicy", {})
        entities = pii_policy.get("piiEntities", []) + pii_policy.get("regexes", [])
        if any(e.get("action") == "BLOCKED" for e in entities):
            return True
    return False


def check_input(text: str, guardrail_id: str, guardrail_version: str) -> str:
    """
    Vérifie la question utilisateur AVANT toute recherche ou génération.
    Bloque prompt injection, contenu toxique, sujets interdits.
    """
    response = _bedrock_runtime.apply_guardrail(
        guardrailIdentifier=guardrail_id,
        guardrailVersion=guardrail_version,
        source="INPUT",
        content=[{"text": {"text": text}}],
    )

    if response["action"] == "GUARDRAIL_INTERVENED" and _is_hard_block(response):
        # On log la raison précise pour l'audit, mais on ne la renvoie JAMAIS à l'utilisateur
        # (renvoyer le détail du filtre déclenché aide un attaquant à affiner son contournement)
        raise ContentBlockedException(response["outputs"][0]["text"])

    return response["outputs"][0]["text"] if response.get("outputs") else text


def check_output(text: str, guardrail_id: str, guardrail_version: str) -> str:
    """
    Vérifie la réponse générée par le LLM AVANT de la renvoyer à l'utilisateur.
    Bloque PII non anonymisées, contenu hors-sujet, réponses non ancrées dans le contexte.
    """
    response = _bedrock_runtime.apply_guardrail(
        guardrailIdentifier=guardrail_id,
        guardrailVersion=guardrail_version,
        source="OUTPUT",
        content=[{"text": {"text": text}}],
    )

    if response["action"] == "GUARDRAIL_INTERVENED" and _is_hard_block(response):
        raise ContentBlockedException(response["outputs"][0]["text"])

    # Si le Guardrail a anonymisé des PII (email, téléphone...), c'est CE texte modifié
    # qu'il faut renvoyer, pas le texte original généré par le LLM
    return response["outputs"][0]["text"] if response.get("outputs") else text
