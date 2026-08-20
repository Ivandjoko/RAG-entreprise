# tests/unit/test_indexer.py
from unittest.mock import MagicMock, patch

from chunking import Chunk
from indexer import index_chunks


def test_index_chunks_never_sets_a_custom_id():
    # OpenSearch Serverless (VECTORSEARCH) rejette tout _id personnalise en create/index -
    # c'est le bug reel qui a bloque l'ingestion en production cette session. Une regression
    # ici romprait l'ingestion silencieusement (l'erreur n'apparait qu'a l'execution reelle).
    client = MagicMock()
    client.search.return_value = {"hits": {"hits": []}}
    chunks = [Chunk(text="hello", chunk_index=0)]

    with patch("indexer.helpers.bulk") as mock_bulk:
        index_chunks(
            client, "idx", "doc1", chunks, [[0.1, 0.2]], "doc1.pdf", ["public"]
        )

    index_actions = mock_bulk.call_args_list[-1].args[1]
    assert all("_id" not in action for action in index_actions)


def test_index_chunks_deletes_existing_chunks_before_reindexing():
    client = MagicMock()
    client.search.return_value = {
        "hits": {"hits": [{"_id": "old-1"}, {"_id": "old-2"}]}
    }
    chunks = [Chunk(text="hello", chunk_index=0)]

    with patch("indexer.helpers.bulk") as mock_bulk:
        index_chunks(client, "idx", "doc1", chunks, [[0.1]], "doc1.pdf", ["public"])

    client.search.assert_called_once_with(
        index="idx",
        body={"query": {"term": {"doc_id": "doc1"}}, "_source": False, "size": 1000},
    )
    assert (
        mock_bulk.call_count == 2
    )  # un bulk pour la suppression, un pour l'indexation
    delete_actions = mock_bulk.call_args_list[0].args[1]
    assert delete_actions == [
        {"_op_type": "delete", "_index": "idx", "_id": "old-1"},
        {"_op_type": "delete", "_index": "idx", "_id": "old-2"},
    ]


def test_index_chunks_skips_delete_bulk_when_nothing_to_remove():
    client = MagicMock()
    client.search.return_value = {"hits": {"hits": []}}
    chunks = [Chunk(text="hello", chunk_index=0)]

    with patch("indexer.helpers.bulk") as mock_bulk:
        index_chunks(client, "idx", "doc1", chunks, [[0.1]], "doc1.pdf", ["public"])

    assert (
        mock_bulk.call_count == 1
    )  # seulement l'indexation, pas de bulk delete a vide


def test_index_chunks_builds_source_documents_with_all_fields():
    client = MagicMock()
    client.search.return_value = {"hits": {"hits": []}}
    chunks = [Chunk(text="hello", chunk_index=0, section_title="Intro")]

    with patch("indexer.helpers.bulk") as mock_bulk:
        index_chunks(
            client, "idx", "doc1", chunks, [[0.1, 0.2]], "doc1.pdf", ["finance-team"]
        )

    index_actions = mock_bulk.call_args_list[-1].args[1]
    assert index_actions == [
        {
            "_op_type": "index",
            "_index": "idx",
            "_source": {
                "doc_id": "doc1",
                "chunk_index": 0,
                "text": "hello",
                "section_title": "Intro",
                "vector": [0.1, 0.2],
                "source": "doc1.pdf",
                "permissions": ["finance-team"],
            },
        }
    ]
