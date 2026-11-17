# parsers.py
from io import BytesIO

import boto3
from bs4 import BeautifulSoup
from docx import Document as DocxDocument
from pypdf import PdfReader

_textract = boto3.client("textract")


def extract_text(file_bytes: bytes, content_type: str, is_scanned: bool = False) -> str:
    """
    Route vers le bon extracteur selon le type de fichier.
    is_scanned force le passage par Textract même pour un PDF
    (utile quand le PDF est une image sans couche texte).
    """
    if content_type == "application/pdf":
        return _extract_pdf(file_bytes, is_scanned)
    elif (
        content_type
        == "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ):
        return _extract_docx(file_bytes)
    elif content_type == "text/html":
        return _extract_html(file_bytes)
    else:
        raise ValueError(f"Type de document non supporté : {content_type}")


def _extract_pdf(file_bytes: bytes, is_scanned: bool) -> str:
    if not is_scanned:
        # Tentative rapide et gratuite avec pypdf d'abord
        reader = PdfReader(BytesIO(file_bytes))
        text = "\n".join(page.extract_text() or "" for page in reader.pages)
        # Si le texte extrait est quasi vide, c'est probablement un scan -> bascule Textract
        if len(text.strip()) > 100:
            return text

    # Textract : plus lent et facturé à la page, réservé aux documents scannés
    response = _textract.detect_document_text(Document={"Bytes": file_bytes})
    lines = [b["Text"] for b in response["Blocks"] if b["BlockType"] == "LINE"]
    return "\n".join(lines)


def _extract_docx(file_bytes: bytes) -> str:
    doc = DocxDocument(BytesIO(file_bytes))
    return "\n".join(p.text for p in doc.paragraphs if p.text.strip())


def _extract_html(file_bytes: bytes) -> str:
    soup = BeautifulSoup(file_bytes, "html.parser")
    # On retire scripts et styles avant extraction, sinon ils polluent le texte
    for tag in soup(["script", "style"]):
        tag.decompose()
    return soup.get_text(separator="\n", strip=True)
