# retrieval.py
import boto3
import json
from opensearchpy import OpenSearch, RequestsAWSV4SignerAuth, RequestsHttpConnection

_bedrock_runtime = boto3.client("bedrock-runtime")

def _get_opensearch_client(collection_endpoint: str, region: str) -> OpenSearch:
    credentials = boto3.Session().get_credentials()
    auth = RequestsAWSV4SignerAuth(credentials, region, "aoss")
    return OpenSearch(
        hosts=[{"host": collection_endpoint.replace("https://", ""), "port": 443}],
        http_auth=auth,
        use_ssl=True,
        connection_class=RequestsHttpConnection,
    )


def embed_query(text: str) -> list[float]:
    """Génère l'embedding de la question utilisateur avec le même modèle que l'ingestion."""
    response = _bedrock_runtime.invoke_model(
        modelId="amazon.titan-embed-text-v2:0",
        body=json.dumps({"inputText": text})
    )
    return json.loads(response["body"].read())["embedding"]


def hybrid_search(
    query_text: str,
    query_vector: list[float],
    allowed_permissions: list[str],
    opensearch_client: OpenSearch,
    index_name: str,
    top_k: int = 25,
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
                "filter": [
                    {"terms": {"permissions": allowed_permissions}}
                ],
                "should": [
                    # Clause vectorielle : similarité sémantique
                    {
                        "knn": {
                            "vector": {"vector": query_vector, "k": top_k}
                        }
                    },
                    # Clause lexicale : correspondance de mots-clés exacts (BM25)
                    # essentielle pour les termes précis (références, codes produit, noms propres)
                    # que la similarité sémantique seule rate souvent
                    {
                        "match": {"text": {"query": query_text, "boost": 0.4}}
                    }
                ]
            }
        }
    }

    response = opensearch_client.search(index=index_name, body=query_body)
    return [
        {
            "text": hit["_source"]["text"],
            "doc_id": hit["_source"]["doc_id"],
            "source": hit["_source"]["source"],
            "score": hit["_score"]
        }
        for hit in response["hits"]["hits"]
    ]


def rerank(query_text: str, candidates: list[dict], top_n: int = 5) -> list[dict]:
    """
    Réordonne les candidats de la recherche hybride par pertinence réelle,
    via le modèle Cohere Rerank sur Bedrock.
    """
    if not candidates:
        return []

    response = _bedrock_runtime.invoke_model(
        modelId="cohere.rerank-v3-5:0",
        body=json.dumps({
            "query": query_text,
            "documents": [c["text"] for c in candidates],
            "top_n": top_n,
            "api_version": 2
        })
    )

    results = json.loads(response["body"].read())["results"]
    # results contient les index triés par pertinence + le score de rerank
    return [
        {**candidates[r["index"]], "rerank_score": r["relevance_score"]}
        for r in results
    ]