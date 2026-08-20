# audit.py
import json
import time

import boto3
from botocore.config import Config

# Sans Config explicite, botocore utilise ses timeouts par defaut (60s) - sans VPC endpoint
# "logs" ni NAT Gateway, un appel bloque hangait silencieusement jusqu'a epuiser tout le
# budget de la Lambda (voir aussi l'endpoint aws_vpc_endpoint.logs ajoute cote networking).
_logs_client = boto3.client(
    "logs",
    config=Config(
        connect_timeout=10,
        read_timeout=15,
        retries={"max_attempts": 2, "mode": "standard"},
    ),
)
LOG_GROUP = "/aws/rag-platform/query-audit"


def log_query(
    user_id: str,
    question: str,
    sources: list[str],
    latency_ms: int,
    status: str,
    error: str | None = None,
):
    """
    Log structuré (JSON) pour permettre des requêtes CloudWatch Insights précises,
    ex: 'combien de requêtes bloquées par le Guardrail cette semaine ?'
    """
    entry = {
        "timestamp": int(time.time() * 1000),
        "user_id": user_id,
        "question_length": len(
            question
        ),  # jamais la question en clair dans les logs si sensible
        "sources_used": sources,
        "latency_ms": latency_ms,
        "status": status,
    }
    if error:
        entry["error"] = error

    log_stream = (
        f"{user_id}-{int(time.time() // 86400)}"  # un stream par jour et par user
    )
    log_event = {"timestamp": entry["timestamp"], "message": json.dumps(entry)}

    try:
        _logs_client.put_log_events(
            logGroupName=LOG_GROUP, logStreamName=log_stream, logEvents=[log_event]
        )
    except _logs_client.exceptions.ResourceNotFoundException:
        # Premier log du jour pour cet utilisateur : le stream n'existe pas encore.
        # On le crée puis on réessaie une fois - l'audit ne doit jamais faire échouer
        # une requête utilisateur par ailleurs réussie.
        _logs_client.create_log_stream(logGroupName=LOG_GROUP, logStreamName=log_stream)
        _logs_client.put_log_events(
            logGroupName=LOG_GROUP, logStreamName=log_stream, logEvents=[log_event]
        )
