# tests/unit/conftest.py
import os
import sys
from pathlib import Path

# Le code Lambda utilise des imports "plats" (from chunking import ...), pas de package
# Python : chaque dossier src/*_lambda/ est zippe tel quel comme unite de deploiement,
# sans __init__.py ni namespace partage. On ajoute donc les deux dossiers au path plutot
# que d'imposer une structure de package qui n'existe pas en production.
_SRC = Path(__file__).resolve().parents[2] / "src"
for _module_dir in ["ingestion_lambda", "query_orchestrator_lambda"]:
    sys.path.insert(0, str(_SRC / _module_dir))

# Plusieurs modules (guardrails.py, retrieval.py, generation.py, metadata_store.py...)
# construisent un client boto3 au niveau module (region requise des l'import, avant meme
# l'execution d'un test) - sans region resolvable, boto3 leve NoRegionError immediatement.
os.environ.setdefault("AWS_DEFAULT_REGION", "eu-west-3")
