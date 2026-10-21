import copy
import json
from datetime import datetime

import pytest
from jsonschema import Draft202012Validator, FormatChecker
from pydantic import ValidationError

from packages.contracts.v1.generate import MODELS, ROOT, artifacts

EXAMPLES = json.loads((ROOT / "examples.json").read_text(encoding="utf-8"))
BUNDLE = json.loads((ROOT / "schemas.json").read_text(encoding="utf-8"))
FORMATS = FormatChecker()


@FORMATS.checks("date-time", raises=ValueError)
def date_time_format(value):
    # Use stdlib parsing instead of jsonschema's optional date-time dependency.
    if not isinstance(value, str):
        return True
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return "T" in value and parsed.tzinfo is not None


def validator(name):
    return Draft202012Validator(
        {**BUNDLE, "$ref": f"#/$defs/{name}"}, format_checker=FORMATS
    )


@pytest.mark.parametrize("name", sorted(MODELS))
def test_examples(name):
    value = EXAMPLES[name]
    validator(name).validate(value)
    assert (
        MODELS[name].model_validate_json(json.dumps(value)).model_dump(mode="json")
        == value
    )


def test_exported_artifacts_are_current():
    for filename, expected in artifacts().items():
        actual = json.loads((ROOT / filename).read_text(encoding="utf-8"))
        assert actual == expected, (
            "Regenerate: python -m packages.contracts.v1.generate"
        )
    Draft202012Validator.check_schema(BUNDLE)


@pytest.mark.parametrize(
    "name,field,value",
    [
        ("RepEvent", "exercise", "burpee"),
        ("RepEvent", "schema_version", "2.0.0"),
        ("RepEvent", "sequence", 0),
        ("RepEvent", "sequence", True),
        ("RepEvent", "confidence", 1.1),
        ("RepEvent", "valid", "true"),
        ("RepEvent", "event_id", "invalid"),
        ("RepEvent", "unexpected", 1),
        ("ScoreUpdate", "revision", 0),
        ("ScoreUpdate", "type", "client.score"),
        ("ScoreUpdate", "participants", []),
        ("Challenge", "participants", []),
        ("ChallengeParticipant", "accepted_reps", -1),
        ("AuthRequest", "password", "short"),
        ("PoseFrame", "timestamp_ms", -1),
        ("PoseFrame", "landmarks", {"unknown": {"x": 0, "y": 0, "confidence": 1}}),
        ("Landmark", "x", 1.1),
        ("WorkoutSession", "started_at", "not-a-date"),
    ],
)
def test_structural_rejections(name, field, value):
    bad = copy.deepcopy(EXAMPLES[name])
    bad[field] = value
    assert list(validator(name).iter_errors(bad))
    with pytest.raises(ValidationError):
        MODELS[name].model_validate_json(json.dumps(bad))


@pytest.mark.parametrize(
    "name,mutate",
    [
        ("RepEvent", lambda v: v.update(ended_at_ms=v["started_at_ms"])),
        ("RepEvent", lambda v: v.update(confidence=0.79)),
        ("WorkoutSession", lambda v: v.update(status="completed")),
        ("WorkoutSession", lambda v: v.update(started_at="2026-10-21T09:00:00+02:00")),
        ("WorkoutSession", lambda v: v.update(started_at="2026-10-21T09:00:00")),
        (
            "WorkoutSession",
            lambda v: v.update(status="completed", ended_at="2026-10-20T09:00:00Z"),
        ),
        ("Challenge", lambda v: v.update(participants=v["participants"][:1])),
        (
            "Challenge",
            lambda v: v["participants"][1].update(
                user_id=v["participants"][0]["user_id"]
            ),
        ),
        ("Challenge", lambda v: v["participants"][1].update(session_id=None)),
        (
            "ScoreUpdate",
            lambda v: v["participants"][1].update(
                session_id=v["participants"][0]["session_id"]
            ),
        ),
        (
            "ScoreUpdate",
            lambda v: v["participants"][1].update(
                user_id=v["participants"][0]["user_id"]
            ),
        ),
        ("RepReceipt", lambda v: v.update(disposition="rejected")),
    ],
)
def test_semantic_rejections(name, mutate):
    bad = copy.deepcopy(EXAMPLES[name])
    mutate(bad)
    with pytest.raises(ValidationError):
        MODELS[name].model_validate_json(json.dumps(bad))


@pytest.mark.parametrize("name", sorted(MODELS))
def test_required_fields(name):
    schema = BUNDLE["$defs"][name]
    for field in schema.get("required", []):
        bad = {k: v for k, v in EXAMPLES[name].items() if k != field}
        assert list(validator(name).iter_errors(bad))
        with pytest.raises(ValidationError):
            MODELS[name].model_validate_json(json.dumps(bad))


def test_rest_references_and_security():
    api = artifacts()["openapi.json"]
    for path, methods in api["paths"].items():
        for operation in methods.values():
            assert bool(operation["security"]) == ("/auth/" not in path)
            for response in operation["responses"].values():
                ref = response["content"]["application/json"]["schema"]["$ref"]
                assert ref.split("/")[-1] in MODELS
            for parameter in operation.get("parameters", []):
                assert "{" + parameter["name"] + "}" in path


def test_waiting_challenge_cannot_already_be_active_or_have_scores():
    value = copy.deepcopy(EXAMPLES["Challenge"])
    value["status"] = "waiting"
    with pytest.raises(ValidationError):
        MODELS["Challenge"].model_validate(value)
    value["participants"][1]["session_id"] = None
    with pytest.raises(ValidationError):
        MODELS["Challenge"].model_validate(value)
    value["participants"][0]["accepted_reps"] = 0
    MODELS["Challenge"].model_validate(value)


def test_rejected_rep_and_receipt_are_representable():
    rep = {**EXAMPLES["RepEvent"], "valid": False, "confidence": 0.5}
    receipt = {
        **EXAMPLES["RepReceipt"],
        "disposition": "rejected",
        "reason": "low_confidence",
        "accepted_reps": 0,
    }
    for name, value in (("RepEvent", rep), ("RepReceipt", receipt)):
        validator(name).validate(value)
        MODELS[name].model_validate(value)
