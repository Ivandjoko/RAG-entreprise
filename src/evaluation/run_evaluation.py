# run_evaluation.py
import sys

sys.path.append("../query_orchestrator_lambda")
from dataset import load_golden_dataset
from generation import generate_answer
from metrics import run_ragas_evaluation
from report import generate_comparison_report
from retrieval import _get_opensearch_client, embed_query, hybrid_search


def evaluate_configuration(
    dataset_path: str, config_name: str, opensearch_client, index_name: str
) -> dict:
    samples = load_golden_dataset(dataset_path)
    eval_rows = []

    for sample in samples:
        query_vector = embed_query(sample.question)
        top_chunks = hybrid_search(
            sample.question,
            query_vector,
            allowed_permissions=["public"],
            opensearch_client=opensearch_client,
            index_name=index_name,
        )
        answer = generate_answer(sample.question, top_chunks)

        eval_rows.append(
            {
                "user_input": sample.question,
                "retrieved_contexts": [c["text"] for c in top_chunks],
                "response": answer,
                "reference": sample.ground_truth,
            }
        )

    scores = run_ragas_evaluation(eval_rows)
    return {"config": config_name, "scores": scores}


if __name__ == "__main__":
    client = _get_opensearch_client(endpoint="...", region="eu-west-3")

    # Comparer plusieurs configurations objectivement - c'est ça qui justifie
    # tes choix techniques face au client avec des chiffres, pas des opinions
    results_semantic = evaluate_configuration(
        "golden_dataset.json", "chunking_semantic", client, "index_semantic"
    )
    results_hierarchical = evaluate_configuration(
        "golden_dataset.json", "chunking_hierarchical", client, "index_hierarchical"
    )

    generate_comparison_report(
        [results_semantic, results_hierarchical], output="report.html"
    )
