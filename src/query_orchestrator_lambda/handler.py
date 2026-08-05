# handler.py
import os
import json
import time
from permissions import get_user_permissions
from guardrails import check_input, check_output, ContentBlockedException
from retrieval import embed_query, hybrid_search, rerank, _get_opensearch_client
from generation import generate_answer
from audit import log_query

# Variables d'environnement injectées par Terraform (jamais codées en dur)
GUARDRAIL_ID = os.environ["GUARDRAIL_ID"]
GUARDRAIL_VERSION = os.environ["GUARDRAIL_VERSION"]
COLLECTION_ENDPOINT = os.environ["OPENSEARCH_COLLECTION_ENDPOINT"]
INDEX_NAME = os.environ["OPENSEARCH_INDEX_NAME"]
METADATA_TABLE = os.environ["METADATA_TABLE_NAME"]
AWS_REGION = os.environ["AWS_REGION"]

# Client OpenSearch créé une fois, réutilisé entre invocations (hors handler = cold start only)
_opensearch_client = _get_opensearch_client(COLLECTION_ENDPOINT, AWS_REGION)


def handler(event, context):
    start_time = time.time()
    user_id = None
    question = None

    try:
        # user_id/question sont extraits DANS le try : une requête malformée (JSON invalide,
        # claims Cognito absentes) doit renvoyer une erreur propre, jamais une exception non
        # gérée qui remonterait un traceback brut au client via API Gateway.
        user_id = event["requestContext"]["authorizer"]["claims"]["sub"]  # injecté par Cognito
        question = json.loads(event["body"])["question"]

        # Étape 1 - Guardrail en entrée : bloque prompt injection AVANT toute recherche
        check_input(question, GUARDRAIL_ID, GUARDRAIL_VERSION)

        # Étape 2 - Résolution des droits utilisateur
        allowed_permissions = get_user_permissions(user_id, METADATA_TABLE)

        # Étape 3 - Recherche hybride, filtrée par permissions
        query_vector = embed_query(question)
        candidates = hybrid_search(
            question, query_vector, allowed_permissions,
            _opensearch_client, INDEX_NAME
        )

        # Étape 4 - Reranking pour ne garder que les meilleurs chunks
        top_chunks = rerank(question, candidates, top_n=5)

        # Étape 5 - Génération de la réponse
        answer = generate_answer(question, top_chunks)

        # Étape 6 - Guardrail en sortie : anonymise PII, bloque hallucinations non ancrées
        safe_answer = check_output(answer, GUARDRAIL_ID, GUARDRAIL_VERSION)

        # Étape 7 - Audit : trace complète de la décision, avant de répondre
        log_query(
            user_id=user_id,
            question=question,
            sources=[c["source"] for c in top_chunks],
            latency_ms=int((time.time() - start_time) * 1000),
            status="success"
        )

        return {
            "statusCode": 200,
            "body": json.dumps({
                "answer": safe_answer,
                "sources": list({c["source"] for c in top_chunks})  # dédupliquées
            })
        }

    except ContentBlockedException:
        log_query(user_id=user_id, question=question, sources=[], 
                   latency_ms=int((time.time() - start_time) * 1000), status="blocked")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Votre requête n'a pas pu être traitée."})
        }

    except Exception as e:
        # Erreur inattendue : on log l'erreur complète côté CloudWatch pour debug,
        # mais on ne renvoie JAMAIS le détail technique à l'utilisateur (fuite d'info)
        log_query(user_id=user_id, question=question, sources=[],
                   latency_ms=int((time.time() - start_time) * 1000), status="error", error=str(e))
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Une erreur est survenue, réessayez."})
        }