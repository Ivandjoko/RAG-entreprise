# tests/unit/test_guardrails.py
from guardrails import _is_hard_block


def test_no_assessments_is_not_a_hard_block():
    assert _is_hard_block({"action": "NONE", "assessments": []}) is False


def test_missing_assessments_key_is_not_a_hard_block():
    assert _is_hard_block({"action": "NONE"}) is False


def test_topic_policy_violation_is_a_hard_block():
    response = {"assessments": [{"topicPolicy": {"topics": [{"name": "finance"}]}}]}
    assert _is_hard_block(response) is True


def test_content_policy_violation_is_a_hard_block():
    response = {"assessments": [{"contentPolicy": {"filters": [{"type": "HATE"}]}}]}
    assert _is_hard_block(response) is True


def test_word_policy_violation_is_a_hard_block():
    response = {"assessments": [{"wordPolicy": {"customWords": [{"match": "foo"}]}}]}
    assert _is_hard_block(response) is True


def test_pii_blocked_entity_is_a_hard_block():
    response = {
        "assessments": [
            {
                "sensitiveInformationPolicy": {
                    "piiEntities": [{"type": "EMAIL", "action": "BLOCKED"}]
                }
            }
        ]
    }
    assert _is_hard_block(response) is True


def test_pii_blocked_regex_is_a_hard_block():
    response = {
        "assessments": [
            {
                "sensitiveInformationPolicy": {
                    "regexes": [{"name": "internal-id", "action": "BLOCKED"}]
                }
            }
        ]
    }
    assert _is_hard_block(response) is True


def test_pii_anonymized_only_is_not_a_hard_block():
    # Le coeur du fix de cette session : une anonymisation pure (email masque en {EMAIL})
    # ne doit jamais etre traitee comme un blocage dur - le texte modifie reste utilisable.
    response = {
        "assessments": [
            {
                "sensitiveInformationPolicy": {
                    "piiEntities": [{"type": "EMAIL", "action": "ANONYMIZED"}]
                }
            }
        ]
    }
    assert _is_hard_block(response) is False


def test_mix_of_anonymized_and_blocked_entities_is_a_hard_block():
    response = {
        "assessments": [
            {
                "sensitiveInformationPolicy": {
                    "piiEntities": [
                        {"type": "EMAIL", "action": "ANONYMIZED"},
                        {"type": "SSN", "action": "BLOCKED"},
                    ]
                }
            }
        ]
    }
    assert _is_hard_block(response) is True


def test_multiple_assessments_short_circuits_on_first_block():
    response = {
        "assessments": [
            {"sensitiveInformationPolicy": {"piiEntities": []}},
            {"topicPolicy": {"topics": [{"name": "legal"}]}},
        ]
    }
    assert _is_hard_block(response) is True
