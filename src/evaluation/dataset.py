# dataset.py
import json
from dataclasses import dataclass


@dataclass
class EvalSample:
    question: str
    ground_truth: str  # réponse de référence, validée par un humain métier
    expected_sources: list[str]  # documents qui DEVRAIENT être retrouvés


def load_golden_dataset(path: str) -> list[EvalSample]:
    """
    Jeu de référence écrit à la main avec le client (10-30 questions représentatives
    de vrais cas d'usage). C'est le dataset le plus fiable mais coûteux à construire -
    à faire en atelier avec les experts métier du client, pas seul dans ton coin.
    """
    with open(path) as f:
        raw = json.load(f)
    return [EvalSample(**item) for item in raw]


def generate_synthetic_dataset(
    documents: list[str], llm_client, n_questions: int = 50
) -> list[EvalSample]:
    """
    Complète le golden dataset avec des questions générées automatiquement
    à partir du corpus réel, pour couvrir plus de cas sans tout écrire à la main.
    Utile en phase de développement, jamais comme SEULE source de vérité en recette finale.
    """
    samples = []
    for doc in documents:
        prompt = f"""À partir de ce texte, génère une question précise et sa réponse exacte.
Réponds en JSON: {{"question": "...", "answer": "..."}}

Texte: {doc[:2000]}"""
        response = llm_client.generate(prompt)
        parsed = json.loads(response)
        samples.append(
            EvalSample(
                question=parsed["question"],
                ground_truth=parsed["answer"],
                expected_sources=[],
            )
        )
    return samples[:n_questions]
