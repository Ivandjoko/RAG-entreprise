# audit.py
import boto3
import json
import time

_logs_client = boto3.client("logs")
LOG_GROUP = "/aws/rag-platform/query-audit"

def log_query(user_id: str, question: str, sources: list[str], 
              latency_ms: int, status: str, error: str = None):
    """
    Log structuré (JSON) pour permettre des requêtes CloudWatch Insights précises,
    ex: 'combien de requêtes bloquées par le Guardrail cette semaine ?'
    """
    entry = {
        "timestamp": int(time.time() * 1000),
        "user_id": user_id,
        "question_length": len(question),   # jamais la question en clair dans les logs si sensible
        "sources_used": sources,
        "latency_ms": latency_ms,
        "status": status,
    }
    if error:
        entry["error"] = error

    _logs_client.put_log_events(
        logGroupName=LOG_GROUP,
        logStreamName=f"{user_id}-{int(time.time() // 86400)}",  # un stream par jour et par user
        logEvents=[{"timestamp": entry["timestamp"], "message": json.dumps(entry)}]
    )