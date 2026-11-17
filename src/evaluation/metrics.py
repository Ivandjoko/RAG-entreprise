# metrics.py
from langchain_aws import ChatBedrock
from ragas import EvaluationDataset, evaluate
from ragas.llms import LangchainLLMWrapper
from ragas.metrics import AnswerRelevancy, ContextPrecision, ContextRecall, Faithfulness


def build_ragas_evaluator_llm():
    """
    RAGAS a besoin d'un LLM juge pour scorer faithfulness/relevancy.
    On utilise Claude via Bedrock - garder le même provider que la prod
    limite les coûts et la complexité opérationnelle.
    """
    # eu-west-3 n'a pas d'accès "In-Region" à ce modèle sur Bedrock - profil d'inférence
    # cross-region "eu" requis (voir aussi generation.py, même remarque).
    bedrock_llm = ChatBedrock(
        model_id="eu.anthropic.claude-sonnet-4-6", region_name="eu-west-3"
    )
    return LangchainLLMWrapper(bedrock_llm)


def run_ragas_evaluation(samples: list[dict]) -> dict:
    """
    samples doit contenir pour chaque question :
    - user_input (la question)
    - retrieved_contexts (les chunks réellement récupérés par ton pipeline)
    - response (la réponse générée par ton pipeline)
    - reference (la réponse de référence du golden dataset)
    """
    dataset = EvaluationDataset.from_list(samples)
    evaluator_llm = build_ragas_evaluator_llm()

    results = evaluate(
        dataset=dataset,
        metrics=[
            Faithfulness(llm=evaluator_llm),
            ContextPrecision(llm=evaluator_llm),
            ContextRecall(llm=evaluator_llm),
            AnswerRelevancy(llm=evaluator_llm),
        ],
    )
    return results.to_pandas().to_dict(orient="records")
