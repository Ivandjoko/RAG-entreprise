# indexer.py
import hashlib
from opensearchpy import OpenSearch, helpers

def _stable_chunk_id(doc_id: str, chunk_index: int) -> str:
    """
    ID déterministe basé sur le doc + l'index du chunk, jamais un UUID aléatoire.
    C'est ce qui rend l'ingestion idempotente : si la Lambda est relancée sur
    le même document (retry S3, re-upload), on écrase le même document au lieu
    d'en créer un doublon dans l'index.
    """
    raw = f"{doc_id}-{chunk_index}"
    return hashlib.sha256(raw.encode()).hexdigest()[:32]


def index_chunks(
    client: OpenSearch,
    index_name: str,
    doc_id: str,
    chunks: list,
    vectors: list[list[float]],
    source: str,
    permissions: list[str],
):
    actions = [
        {
            "_op_type": "index",   # 'index' et non 'create' : écrase si l'ID existe déjà -> idempotent
            "_index": index_name,
            "_id": _stable_chunk_id(doc_id, chunk.chunk_index),
            "_source": {
                "doc_id": doc_id,
                "chunk_index": chunk.chunk_index,
                "text": chunk.text,
                "section_title": chunk.section_title,
                "vector": vector,
                "source": source,
                "permissions": permissions,
            }
        }
        for chunk, vector in zip(chunks, vectors)
    ]
    # bulk() envoie tous les chunks d'un document en un seul aller-retour réseau
    helpers.bulk(client, actions)