# guardrails.py
import boto3
import json
from botocore.config import Config

_bedrock_runtime = boto3.client(
    "bedrock-runtime",
    config=Config(connect_timeout=10, read_timeout=30, retries={"max_attempts": 5, "mode": "adaptive"}),
)

class ContentBlockedException(Exception):
    """Levée quand le Guardrail bloque le contenu - jamais silencieusement ignorée."""
    pass

def check_input(text: str, guardrail_id: str, guardrail_version: str) -> str:
    """
    Vérifie la question utilisateur AVANT toute recherche ou génération.
    Bloque prompt injection, contenu toxique, sujets interdits.
    """
    response = _bedrock_runtime.apply_guardrail(
        guardrailIdentifier=guardrail_id,
        guardrailVersion=guardrail_version,
        source="INPUT",
        content=[{"text": {"text": text}}]
    )

    if response["action"] == "GUARDRAIL_INTERVENED":
        # On log la raison précise pour l'audit, mais on ne la renvoie JAMAIS à l'utilisateur
        # (renvoyer le détail du filtre déclenché aide un attaquant à affiner son contournement)
        raise ContentBlockedException(response["outputs"][0]["text"])

    return text


def check_output(text: str, guardrail_id: str, guardrail_version: str) -> str:
    """
    Vérifie la réponse générée par le LLM AVANT de la renvoyer à l'utilisateur.
    Bloque PII non anonymisées, contenu hors-sujet, réponses non ancrées dans le contexte.
    """
    response = _bedrock_runtime.apply_guardrail(
        guardrailIdentifier=guardrail_id,
        guardrailVersion=guardrail_version,
        source="OUTPUT",
        content=[{"text": {"text": text}}]
    )

    if response["action"] == "GUARDRAIL_INTERVENED":
        raise ContentBlockedException(response["outputs"][0]["text"])

    # Si le Guardrail a anonymisé des PII (email, téléphone...), c'est CE texte modifié
    # qu'il faut renvoyer, pas le texte original généré par le LLM
    return response["outputs"][0]["text"] if response.get("outputs") else text