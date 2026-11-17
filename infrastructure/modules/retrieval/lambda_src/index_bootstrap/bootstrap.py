# bootstrap.py
import json
import os
import boto3
from opensearchpy import OpenSearch, RequestsAWSV4SignerAuth, RequestsHttpConnection


def _get_opensearch_client(collection_endpoint: str, region: str) -> OpenSearch:
    credentials = boto3.Session().get_credentials()
    auth = RequestsAWSV4SignerAuth(credentials, region, "aoss")
    return OpenSearch(
        hosts=[{"host": collection_endpoint.replace("https://", ""), "port": 443}],
        http_auth=auth,
        use_ssl=True,
        connection_class=RequestsHttpConnection,
    )


def handler(event, context):
    """
    Crée l'index vectoriel s'il n'existe pas déjà - idempotent, invoqué par Terraform
    (aws_lambda_invocation) à chaque apply, mais ne fait rien si l'index est déjà là.
    """
    collection_endpoint = event["collection_endpoint"]
    index_name = event["index_name"]
    mapping_file = event["mapping_file"]

    region = os.environ["AWS_REGION"]
    client = _get_opensearch_client(collection_endpoint, region)

    if client.indices.exists(index=index_name):
        return {"status": "already_exists", "index_name": index_name}

    with open(mapping_file) as f:
        mapping = json.load(f)

    client.indices.create(index=index_name, body=mapping)
    return {"status": "created", "index_name": index_name}
