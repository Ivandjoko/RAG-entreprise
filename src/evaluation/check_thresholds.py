# check_thresholds.py
import json
import sys
import argparse

def check_thresholds(scores_path: str, min_faithfulness: float, min_recall: float):
    with open(scores_path) as f:
        scores = json.load(f)

    avg_faithfulness = sum(s["faithfulness"] for s in scores) / len(scores)
    avg_recall = sum(s["context_recall"] for s in scores) / len(scores)

    print(f"Faithfulness moyenne: {avg_faithfulness:.2f} (seuil: {min_faithfulness})")
    print(f"Context recall moyen: {avg_recall:.2f} (seuil: {min_recall})")

    if avg_faithfulness < min_faithfulness or avg_recall < min_recall:
        print("ÉCHEC: la qualité du RAG est sous le seuil, déploiement bloqué.")
        sys.exit(1)  # fait échouer le job GitHub Actions, bloque le déploiement prod

    print("Seuils respectés, déploiement autorisé.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--min-faithfulness", type=float, required=True)
    parser.add_argument("--min-recall", type=float, required=True)
    args = parser.parse_args()
    check_thresholds(args.input, args.min_faithfulness, args.min_recall)