# handler.py
import os
import json
import time
from permissions import get_user_permissions
from guardrails import check_input, check_output, ContentBlockedException
from retrieval import embed_query, hybrid_search, _get_opensearch_client
from generation import generate_answer
from audit import log_query

# Variables d'environnement injectées par Terraform (jamais codées en dur)
GUARDRAIL_ID = os.environ["GUARDRAIL_ID"]
GUARDRAIL_VERSION = os.environ["GUARDRAIL_VERSION"]
COLLECTION_ENDPOINT = os.environ["OPENSEARCH_COLLECTION_ENDPOINT"]
INDEX_NAME = os.environ["OPENSEARCH_INDEX_NAME"]
USER_PERMISSIONS_TABLE = os.environ["USER_PERMISSIONS_TABLE_NAME"]
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
        print(f"[0/6] user_id={user_id} question={question!r}")

        # Étape 1 - Guardrail en entrée : bloque prompt injection AVANT toute recherche
        print("[1/6] Appel Bedrock ApplyGuardrail (input)...")
        check_input(question, GUARDRAIL_ID, GUARDRAIL_VERSION)
        print("[1/6] OK")

        # Étape 2 - Résolution des droits utilisateur
        print("[2/6] Lecture DynamoDB (user_permissions)...")
        allowed_permissions = get_user_permissions(user_id, USER_PERMISSIONS_TABLE)
        print(f"[2/6] OK - permissions={allowed_permissions}")

        # Étape 3 - Recherche hybride, filtrée par permissions (pas de rerank derrière :
        # aucun modèle de rerank Bedrock n'est disponible depuis eu-west-3 sans NAT Gateway,
        # hybrid_search renvoie donc directement le top_k final)
        print("[3/6] Appel Bedrock (embed_query)...")
        query_vector = embed_query(question)
        print("[3/6] OK - appel OpenSearch (hybrid_search)...")
        top_chunks = hybrid_search(
            question, query_vector, allowed_permissions,
            _opensearch_client, INDEX_NAME
        )
        print(f"[3/6] OK - {len(top_chunks)} chunks retenus")

        # Étape 4 - Génération de la réponse
        print("[4/6] Appel Bedrock (generate_answer)...")
        answer = generate_answer(question, top_chunks)
        print("[4/6] OK")

        # Étape 5 - Guardrail en sortie : anonymise PII, bloque hallucinations non ancrées
        print("[5/6] Appel Bedrock ApplyGuardrail (output)...")
        safe_answer = check_output(answer, GUARDRAIL_ID, GUARDRAIL_VERSION)
        print("[5/6] OK")

        # Étape 6 - Audit : trace complète de la décision, avant de répondre
        print("[6/6] Ecriture CloudWatch Logs (audit)...")
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
        print("[BLOCKED] Contenu bloque par le Guardrail")
        log_query(user_id=user_id, question=question, sources=[],
                   latency_ms=int((time.time() - start_time) * 1000), status="blocked")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Votre requête n'a pas pu être traitée."})
        }

    except Exception as e:
        # Erreur inattendue : on log l'erreur complète côté CloudWatch pour debug,
        # mais on ne renvoie JAMAIS le détail technique à l'utilisateur (fuite d'info)
        # print() explicite car log_query() écrit dans un log group séparé
        # (/aws/rag-platform/query-audit), pas dans le log stream de la fonction elle-même.
        print(f"[ERROR] {type(e).__name__}: {e}")
        log_query(user_id=user_id, question=question, sources=[],
                   latency_ms=int((time.time() - start_time) * 1000), status="error", error=str(e))
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Une erreur est survenue, réessayez."})
        }