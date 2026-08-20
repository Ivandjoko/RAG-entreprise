# indexer.py
from opensearchpy import OpenSearch, helpers


def index_chunks(
    client: OpenSearch,
    index_name: str,
    doc_id: str,
    chunks: list,
    vectors: list[list[float]],
    source: str,
    permissions: list[str],
):
    # OpenSearch Serverless (collections VECTORSEARCH) refuse tout _id personnalise en
    # create/index ("Document ID is not supported in create/index operation request") et
    # ne supporte pas non plus _delete_by_query. Pour rester idempotent sur un re-upload
    # (retry S3, re-upload manuel), on retrouve d'abord les _id auto-generes des anciens
    # chunks de ce document via une recherche, puis on les supprime individuellement avant
    # de reindexer.
    existing = client.search(
        index=index_name,
        body={"query": {"term": {"doc_id": doc_id}}, "_source": False, "size": 1000},
    )
    delete_actions = [
        {"_op_type": "delete", "_index": index_name, "_id": hit["_id"]}
        for hit in existing["hits"]["hits"]
    ]
    if delete_actions:
        helpers.bulk(client, delete_actions)

    actions = [
        {
            "_op_type": "index",
            "_index": index_name,
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
    # bulk() envoie tous les chunks d'un document en un seul aller-retour reseau
    helpers.bulk(client, actions)
