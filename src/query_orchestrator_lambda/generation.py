# generation.py
import boto3
import json

_bedrock_runtime = boto3.client("bedrock-runtime")

SYSTEM_PROMPT = """Tu réponds aux questions UNIQUEMENT à partir du contexte fourni ci-dessous.
Si le contexte ne contient pas l'information nécessaire, dis-le explicitement.
Ne jamais inventer d'information absente du contexte.
Cite la source (nom du document) pour chaque affirmation factuelle."""

def build_context(chunks: list[dict]) -> str:
    """Assemble les chunks retenus en un contexte structuré, avec traçabilité de la source."""
    return "\n\n".join(
        f"[Source: {c['source']}]\n{c['text']}"
        for c in chunks
    )


def generate_answer(question: str, context_chunks: list[dict]) -> str:
    context = build_context(context_chunks)

    response = _bedrock_runtime.invoke_model(
        # eu-west-3 n'a pas d'accès "In-Region" à ce modèle sur Bedrock - seul le
        # profil d'inférence cross-region "eu" est disponible depuis cette région.
        modelId="eu.anthropic.claude-sonnet-4-6",
        body=json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1024,
            "system": SYSTEM_PROMPT,
            "messages": [{
                "role": "user",
                "content": f"Contexte :\n{context}\n\nQuestion : {question}"
            }]
        })
    )

    return json.loads(response["body"].read())["content"][0]["text"]