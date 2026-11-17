# chunking.py
import re
from dataclasses import dataclass


@dataclass
class Chunk:
    text: str
    chunk_index: int
    section_title: str | None = None


def chunk_document(
    text: str,
    strategy: str = "semantic",
    max_tokens: int = 400,
    overlap_tokens: int = 50,
) -> list[Chunk]:
    """
    Route vers la stratégie de chunking adaptée.
    - fixed: rapide, pour du texte peu structuré
    - semantic: respecte les paragraphes/phrases, le choix par défaut
    - hierarchical: respecte les titres de section, pour les docs structurés (contrats, specs)
    """
    if strategy == "fixed":
        return _chunk_fixed(text, max_tokens, overlap_tokens)
    elif strategy == "semantic":
        return _chunk_semantic(text, max_tokens, overlap_tokens)
    elif strategy == "hierarchical":
        return _chunk_hierarchical(text, max_tokens, overlap_tokens)
    raise ValueError(f"Stratégie inconnue : {strategy}")


def _estimate_tokens(text: str) -> int:
    # Approximation rapide sans dépendance à un tokenizer complet (~4 caractères par token en français/anglais)
    return len(text) // 4


def _chunk_fixed(text: str, max_tokens: int, overlap_tokens: int) -> list[Chunk]:
    """Découpe brutale par nombre de caractères, avec chevauchement. À éviter sauf texte non structuré."""
    max_chars = max_tokens * 4
    overlap_chars = overlap_tokens * 4
    chunks = []
    start = 0
    index = 0
    while start < len(text):
        end = start + max_chars
        chunks.append(Chunk(text=text[start:end], chunk_index=index))
        start = end - overlap_chars  # chevauchement pour ne pas couper une idée en deux
        index += 1
    return chunks


def _chunk_semantic(text: str, max_tokens: int, overlap_tokens: int) -> list[Chunk]:
    """
    Découpe en respectant les frontières de paragraphes, puis regroupe
    des paragraphes consécutifs jusqu'à approcher max_tokens.
    C'est la stratégie par défaut : bon compromis qualité/simplicité.
    """
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    chunks = []
    current = []
    current_tokens = 0
    index = 0

    for para in paragraphs:
        para_tokens = _estimate_tokens(para)

        if current_tokens + para_tokens > max_tokens and current:
            chunks.append(Chunk(text="\n\n".join(current), chunk_index=index))
            index += 1
            # Chevauchement sémantique : on garde le dernier paragraphe du chunk précédent
            # comme contexte de départ du suivant, plutôt qu'un chevauchement de caractères brut
            current = [current[-1]] if overlap_tokens > 0 else []
            current_tokens = _estimate_tokens(current[0]) if current else 0

        current.append(para)
        current_tokens += para_tokens

    if current:
        chunks.append(Chunk(text="\n\n".join(current), chunk_index=index))

    return chunks


def _chunk_hierarchical(text: str, max_tokens: int, overlap_tokens: int) -> list[Chunk]:
    """
    Détecte les titres de section (markdown # ou numérotation type '1.2.3')
    et garde le titre de section attaché à chaque chunk pour l'inclure dans le contexte.
    Idéal pour contrats, spécifications techniques, documentation structurée.
    """
    section_pattern = re.compile(
        r"^(#{1,3}\s+.+|^\d+(\.\d+)*\.?\s+[A-ZÀ-Ü].+)$", re.MULTILINE
    )
    sections = []
    last_pos = 0
    current_title = None

    for match in section_pattern.finditer(text):
        if last_pos < match.start():
            sections.append((current_title, text[last_pos : match.start()]))
        current_title = match.group().strip()
        last_pos = match.end()
    sections.append((current_title, text[last_pos:]))

    chunks = []
    index = 0
    for title, content in sections:
        # Chaque section est ensuite chunkée sémantiquement si elle dépasse max_tokens
        for sub_chunk in _chunk_semantic(content, max_tokens, overlap_tokens):
            chunks.append(
                Chunk(text=sub_chunk.text, chunk_index=index, section_title=title)
            )
            index += 1

    return chunks
