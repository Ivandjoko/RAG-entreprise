# tests/unit/test_chunking.py
import pytest
from chunking import chunk_document


def test_semantic_chunking_keeps_short_text_in_one_chunk():
    text = "Premier paragraphe.\n\nDeuxieme paragraphe."
    chunks = chunk_document(text, strategy="semantic", max_tokens=400)

    assert len(chunks) == 1
    assert "Premier paragraphe." in chunks[0].text
    assert "Deuxieme paragraphe." in chunks[0].text
    assert chunks[0].chunk_index == 0


def test_semantic_chunking_splits_when_exceeding_max_tokens():
    # ~4 caracteres par token (voir _estimate_tokens) : un paragraphe de 800 caracteres
    # depasse a lui seul max_tokens=100 (400 caracteres), donc chaque paragraphe force
    # un nouveau chunk.
    para_a = "a" * 800
    para_b = "b" * 800
    text = f"{para_a}\n\n{para_b}"

    chunks = chunk_document(text, strategy="semantic", max_tokens=100, overlap_tokens=0)

    assert len(chunks) == 2
    assert para_a in chunks[0].text
    assert para_b in chunks[1].text
    assert [c.chunk_index for c in chunks] == [0, 1]


def test_semantic_chunking_ignores_empty_paragraphs():
    text = "Paragraphe A.\n\n\n\n   \n\nParagraphe B."
    chunks = chunk_document(text, strategy="semantic", max_tokens=400)

    assert len(chunks) == 1
    assert chunks[0].text == "Paragraphe A.\n\nParagraphe B."


def test_hierarchical_chunking_attaches_section_titles():
    text = (
        "# Introduction\n"
        "Contenu de l'intro.\n\n"
        "# Conclusion\n"
        "Contenu de la conclusion."
    )
    chunks = chunk_document(text, strategy="hierarchical", max_tokens=400)

    titles = [c.section_title for c in chunks]
    assert "# Introduction" in titles
    assert "# Conclusion" in titles
    intro_chunk = next(c for c in chunks if c.section_title == "# Introduction")
    assert "Contenu de l'intro." in intro_chunk.text


def test_hierarchical_chunking_handles_text_before_first_heading():
    text = "Preambule sans titre.\n\n# Section 1\nContenu."
    chunks = chunk_document(text, strategy="hierarchical", max_tokens=400)

    preamble_chunk = chunks[0]
    assert preamble_chunk.section_title is None
    assert "Preambule sans titre." in preamble_chunk.text


def test_fixed_chunking_respects_max_chars_and_overlap():
    # Caracteres distincts (pas de repetition uniforme) pour que les slices attendues
    # ci-dessous soient une vraie verification positionnelle, pas une tautologie.
    text = "".join(str(i % 10) for i in range(1000))
    chunks = chunk_document(text, strategy="fixed", max_tokens=100, overlap_tokens=10)

    # max_chars = 100*4 = 400, overlap_chars = 10*4 = 40 -> start suivant = end - 40
    assert [c.text for c in chunks] == [
        text[0:400],
        text[360:760],
        text[720:1000],
    ]
    assert [c.chunk_index for c in chunks] == [0, 1, 2]


def test_unknown_strategy_raises():
    with pytest.raises(ValueError):
        chunk_document("texte", strategy="magique")
