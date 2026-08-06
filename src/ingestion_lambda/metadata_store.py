# metadata_store.py
import boto3
import time

_dynamodb = boto3.resource("dynamodb")

def write_document_metadata(
    table_name: str,
    doc_id: str,
    source_key: str,
    permissions: list[str],
    chunk_count: int,
    status: str = "indexed",
):
    table = _dynamodb.Table(table_name)
    table.put_item(Item={
        "doc_id": doc_id,
        "source_key": source_key,
        "permissions": permissions,
        "chunk_count": chunk_count,
        "status": status,
        "indexed_at": int(time.time()),
    })


def resolve_permissions(source_key: str) -> list[str]:
    """
    Détermine les tags de permission d'un document à partir de son chemin S3.
    Convention : documents/{permission_group}/{filename}
    Ex: documents/finance-team/budget-2026.pdf -> ["finance-team"]
    Une convention de nommage simple, documentée, plutôt qu'un système de tagging
    complexe à ce stade - suffisant pour la majorité des cas clients.
    """
    parts = source_key.split("/")
    if len(parts) >= 2 and parts[0] == "documents":
        return [parts[1]]
    return ["public"]  # fail closed : par défaut, accès le plus restrictif