# tests/unit/test_retrieval.py
from unittest.mock import MagicMock

from retrieval import hybrid_search


def _fake_hit(text, doc_id, source, score):
    return {
        "_score": score,
        "_source": {"text": text, "doc_id": doc_id, "source": source},
    }


def test_hybrid_search_builds_query_with_permission_filter_and_knn_and_bm25():
    client = MagicMock()
    client.search.return_value = {"hits": {"hits": []}}

    hybrid_search(
        query_text="qui est Ivan ?",
        query_vector=[0.1, 0.2, 0.3],
        allowed_permissions=["public", "finance-team"],
        opensearch_client=client,
        index_name="rag-index-dev",
        top_k=7,
    )

    client.search.assert_called_once()
    call_kwargs = client.search.call_args.kwargs
    assert call_kwargs["index"] == "rag-index-dev"

    query_body = call_kwargs["body"]
    assert query_body["size"] == 7
    bool_query = query_body["query"]["bool"]
    # Le filtre de permissions doit exclure les documents hors scope, pas juste les
    # deprioriser - c'est un "filter", jamais un "should" avec un boost.
    assert bool_query["filter"] == [
        {"terms": {"permissions": ["public", "finance-team"]}}
    ]
    should_clauses = bool_query["should"]
    assert {"knn": {"vector": {"vector": [0.1, 0.2, 0.3], "k": 7}}} in should_clauses
    assert {
        "match": {"text": {"query": "qui est Ivan ?", "boost": 0.4}}
    } in should_clauses


def test_hybrid_search_maps_hits_to_flat_dicts():
    client = MagicMock()
    client.search.return_value = {
        "hits": {
            "hits": [
                _fake_hit("Texte A", "doc-a", "a.pdf", 1.9),
                _fake_hit("Texte B", "doc-b", "b.pdf", 0.5),
            ]
        }
    }

    results = hybrid_search(
        query_text="question",
        query_vector=[0.0],
        allowed_permissions=["public"],
        opensearch_client=client,
        index_name="idx",
    )

    assert results == [
        {"text": "Texte A", "doc_id": "doc-a", "source": "a.pdf", "score": 1.9},
        {"text": "Texte B", "doc_id": "doc-b", "source": "b.pdf", "score": 0.5},
    ]


def test_hybrid_search_returns_empty_list_when_no_hits():
    client = MagicMock()
    client.search.return_value = {"hits": {"hits": []}}

    results = hybrid_search(
        query_text="question",
        query_vector=[0.0],
        allowed_permissions=["public"],
        opensearch_client=client,
        index_name="idx",
    )

    assert results == []


def test_hybrid_search_default_top_k_is_five():
    client = MagicMock()
    client.search.return_value = {"hits": {"hits": []}}

    hybrid_search(
        query_text="q",
        query_vector=[0.0],
        allowed_permissions=["public"],
        opensearch_client=client,
        index_name="idx",
    )

    body = client.search.call_args.kwargs["body"]
    assert body["size"] == 5
