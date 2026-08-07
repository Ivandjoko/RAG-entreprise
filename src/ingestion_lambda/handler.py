# handler.py
import os
import json
import boto3
from parsers import extract_text
from chunking import chunk_document
from embeddings import embed_chunks
from indexer import index_chunks
from metadata_store import write_document_metadata, resolve_permissions
from opensearch_client import get_opensearch_client

s3 = boto3.client("s3")

INDEX_NAME = os.environ["OPENSEARCH_INDEX_NAME"]
COLLECTION_ENDPOINT = os.environ["OPENSEARCH_COLLECTION_ENDPOINT"]
METADATA_TABLE = os.environ["METADATA_TABLE_NAME"]
AWS_REGION = os.environ["AWS_REGION"]

_opensearch_client = get_opensearch_client(COLLECTION_ENDPOINT, AWS_REGION)


def handler(event, context):
    # Événement EventBridge (Object Created) - on extrait bucket et clé
    detail = event["detail"]
    bucket = detail["bucket"]["name"]
    key = detail["object"]["key"]

    try:
        print(f"[1/6] S3 GetObject bucket={bucket} key={key}")
        response = s3.get_object(Bucket=bucket, Key=key)
        file_bytes = response["Body"].read()
        content_type = response["ContentType"]
        print(f"[1/6] OK - {len(file_bytes)} bytes, content_type={content_type}")

        # 1. Extraction du texte selon le type de fichier
        text = extract_text(file_bytes, content_type)
        print(f"[2/6] Extraction OK - {len(text)} caracteres")

        if len(text.strip()) < 20:
            # Document vide ou extraction échouée -> on log et on s'arrête,
            # jamais d'indexation d'un chunk quasi-vide qui polluerait la recherche
            write_document_metadata(METADATA_TABLE, doc_id=key, source_key=key,
                                     permissions=[], chunk_count=0, status="extraction_failed")
            return {"statusCode": 422, "body": "Extraction de texte vide"}

        # 2. Chunking (hierarchical par défaut pour PDF/DOCX, semantic pour HTML)
        strategy = "hierarchical" if content_type != "text/html" else "semantic"
        chunks = chunk_document(text, strategy=strategy)
        print(f"[3/6] Chunking OK - {len(chunks)} chunks (strategy={strategy})")

        # 3. Résolution des permissions à partir du chemin S3
        permissions = resolve_permissions(key)
        print(f"[3/6] Permissions resolues: {permissions}")

        # 4. Génération des embeddings
        print("[4/6] Appel Bedrock (embeddings)...")
        vectors = embed_chunks([c.text for c in chunks])
        print(f"[4/6] OK - {len(vectors)} vecteurs generes")

        # 5. Indexation dans OpenSearch (idempotente grâce aux IDs déterministes)
        print("[5/6] Appel OpenSearch (bulk index)...")
        index_chunks(
            _opensearch_client, INDEX_NAME, doc_id=key,
            chunks=chunks, vectors=vectors, source=key, permissions=permissions
        )
        print("[5/6] OK - indexation terminee")

        # 6. Écriture des métadonnées de suivi
        write_document_metadata(
            METADATA_TABLE, doc_id=key, source_key=key,
            permissions=permissions, chunk_count=len(chunks), status="indexed"
        )
        print("[6/6] OK - metadonnees ecrites")

        return {"statusCode": 200, "body": json.dumps({"chunks_indexed": len(chunks)})}

    except Exception:
        # En échec, on écrit le statut en DynamoDB plutôt que de laisser l'échec silencieux -
        # ça permet un dashboard "documents en erreur" consultable par un opérateur
        write_document_metadata(METADATA_TABLE, doc_id=key, source_key=key,
                                 permissions=[], chunk_count=0, status="error")
        raise  # on relance l'exception pour que Lambda déclenche sa politique de retry / DLQ
