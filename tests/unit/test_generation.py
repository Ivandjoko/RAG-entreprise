# tests/unit/test_generation.py
from generation import build_context


def test_build_context_formats_single_chunk_with_source():
    chunks = [{"source": "doc.pdf", "text": "Contenu du document."}]
    assert build_context(chunks) == "[Source: doc.pdf]\nContenu du document."


def test_build_context_joins_multiple_chunks_with_blank_line():
    chunks = [
        {"source": "a.pdf", "text": "Texte A."},
        {"source": "b.pdf", "text": "Texte B."},
    ]
    assert (
        build_context(chunks)
        == "[Source: a.pdf]\nTexte A.\n\n[Source: b.pdf]\nTexte B."
    )


def test_build_context_empty_list_returns_empty_string():
    assert build_context([]) == ""
