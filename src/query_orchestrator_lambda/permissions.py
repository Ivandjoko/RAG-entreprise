# permissions.py
import boto3
from botocore.config import Config

# Client réutilisé entre invocations (cold start optimisé) - jamais recréé dans le handler
_dynamodb = boto3.resource("dynamodb", config=Config(retries={"max_attempts": 3}))

def get_user_permissions(user_id: str, table_name: str) -> list[str]:
    """
    Retourne la liste des tags de permission auxquels l'utilisateur a accès.
    Ex: ["public", "finance-team", "hr-confidential"]
    """
    table = _dynamodb.Table(table_name)
    response = table.get_item(Key={"user_id": user_id})

    if "Item" not in response:
        # Utilisateur inconnu = accès public uniquement, jamais un accès par défaut large
        return ["public"]

    return response["Item"].get("permission_groups", ["public"])