# embeddings.py
import boto3
import json

_bedrock_runtime = boto3.client("bedrock-runtime")

def embed_chunks(chunks: list[str], batch_size: int = 10) -> list[list[float]]:
    """
    Titan Embeddings ne supporte pas le batch natif -> on parallélise nous-mêmes
    par petits lots pour limiter le risque de throttling Bedrock.
    """
    embeddings = []
    for i in range(0, len(chunks), batch_size):
        batch = chunks[i:i + batch_size]
        for text in batch:
            response = _bedrock_runtime.invoke_model(
                modelId="amazon.titan-embed-text-v2:0",
                body=json.dumps({"inputText": text})
            )
            embeddings.append(json.loads(response["body"].read())["embedding"])
    return embeddings