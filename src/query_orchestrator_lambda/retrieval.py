# retrieval.py
import json

import boto3
from botocore.config import Config
from opensearchpy import OpenSearch, RequestsAWSV4SignerAuth, RequestsHttpConnection

_bedrock_runtime = boto3.client(
    "bedrock-runtime",
    # mode "standard" et non "adaptive" : voir embeddings.py pour le raisonnement (limiteur
    # de debit cote client persistant entre invocations Lambda "warm").
    # read_timeout/max_attempts volontairement bas ici (diagnostic) : avec 30s*5 tentatives,
    # botocore epuisait le timeout Lambda (60s) AVANT de lever l'exception finale - le except
    # du handler ne recevait donc jamais d'erreur exploitable, juste un kill silencieux.
    config=Config(
        connect_timeout=10,
        read_timeout=15,
        retries={"max_attempts": 2, "mode": "standard"},
    ),
)


def _get_opensearch_client(collection_endpoint: str, region: str) -> OpenSearch:
    credentials = boto3.Session().get_credentials()
    auth = RequestsAWSV4SignerAuth(credentials, region, "aoss")
    return OpenSearch(
        hosts=[{"host": collection_endpoint.replace("https://", ""), "port": 443}],
        http_auth=auth,
        use_ssl=True,
        connection_class=RequestsHttpConnection,
        timeout=30,
    )


def embed_query(text: str) -> list[float]:
    """Génère l'embedding de la question utilisateur avec le même modèle que l'ingestion."""
    response = _bedrock_runtime.invoke_model(
        modelId="amazon.titan-embed-text-v2:0", body=json.dumps({"inputText": text})
    )
    return json.loads(response["body"].read())["embedding"]


def hybrid_search(
    query_text: str,
    query_vector: list[float],
    allowed_permissions: list[str],
    opensearch_client: OpenSearch,
    index_name: str,
    # Pas d'étape de rerank derrière (Cohere Rerank et Amazon Rerank ne sont disponibles
    # dans aucune région accessible depuis eu-west-3 sans NAT Gateway - voir git history) :
    # top_k renvoie directement le nombre final de chunks passés à la génération.
    top_k: int = 5,
) -> list[dict]:
    """
    Combine recherche vectorielle (kNN) et recherche lexicale (BM25),
    filtrée par les permissions résolues de l'utilisateur.
    """
    query_body = {
        "size": top_k,
        "query": {
            "bool": {
                # Le filtre de permissions s'applique AVANT le scoring - c'est une exclusion dure,
                # pas une pondération. Un document hors scope n'apparaît jamais, même mal classé.
                "filter": [{"terms": {"permissions": allowed_permissions}}],
                "should": [
                    # Clause vectorielle : similarité sémantique
                    {"knn": {"vector": {"vector": query_vector, "k": top_k}}},
                    # Clause lexicale : correspondance de mots-clés exacts (BM25)
                    # essentielle pour les termes précis (références, codes produit, noms propres)
                    # que la similarité sémantique seule rate souvent
                    {"match": {"text": {"query": query_text, "boost": 0.4}}},
                ],
            }
        },
    }

    response = opensearch_client.search(index=index_name, body=query_body)
    return [
        {
            "text": hit["_source"]["text"],
            "doc_id": hit["_source"]["doc_id"],
            "source": hit["_source"]["source"],
            "score": hit["_score"],
        }
        for hit in response["hits"]["hits"]
    ]
