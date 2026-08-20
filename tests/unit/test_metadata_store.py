# tests/unit/test_metadata_store.py
from metadata_store import resolve_permissions


def test_resolve_permissions_extracts_group_from_documents_path():
    assert resolve_permissions("documents/finance-team/budget-2026.pdf") == [
        "finance-team"
    ]


def test_resolve_permissions_extracts_public_group():
    assert resolve_permissions("documents/public/brochure.pdf") == ["public"]


def test_resolve_permissions_defaults_to_public_when_no_documents_prefix():
    # Fail closed : un chemin qui ne suit pas la convention doit rester restrictif,
    # jamais suppose "sans permission" ou lever une exception.
    assert resolve_permissions("random-file.pdf") == ["public"]


def test_resolve_permissions_defaults_to_public_when_path_too_short():
    assert resolve_permissions("documents") == ["public"]


def test_resolve_permissions_ignores_nested_path_segments():
    assert resolve_permissions("documents/hr-confidential/2026/salaries.xlsx") == [
        "hr-confidential"
    ]
