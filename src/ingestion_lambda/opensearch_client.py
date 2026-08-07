# opensearch_client.py
# Dupliqué depuis src/query_orchestrator_lambda/retrieval.py : chaque Lambda est packagée
# indépendamment (zip séparé), donc pas d'import cross-package possible entre les deux.
from opensearchpy import OpenSearch, RequestsAWSV4SignerAuth, RequestsHttpConnection
import boto3


def get_opensearch_client(collection_endpoint: str, region: str) -> OpenSearch:
    credentials = boto3.Session().get_credentials()
    auth = RequestsAWSV4SignerAuth(credentials, region, "aoss")
    return OpenSearch(
        hosts=[{"host": collection_endpoint.replace("https://", ""), "port": 443}],
        http_auth=auth,
        use_ssl=True,
        connection_class=RequestsHttpConnection,
        timeout=30,  # sans ça, un souci réseau fait pendre l'appel jusqu'au timeout Lambda
    )
