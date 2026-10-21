"""Generate portable artifacts: python -m packages.contracts.v1.generate."""

import json
from pathlib import Path

from . import models

ROOT = Path(__file__).parent
MODELS = {
    name: value
    for name, value in vars(models).items()
    if isinstance(value, type)
    and issubclass(value, models.Contract)
    and value != models.Contract
}


def schemas(ref_template):
    result = {}
    for name, model in MODELS.items():
        schema = model.model_json_schema(ref_template=ref_template)
        result.update(schema.pop("$defs", {}))
        result[name] = schema
    return result


def openapi():
    paths = {}

    def operation(path, method, name, response, status=200, request=None, public=False):
        responses = {
            str(status): {
                "description": "Success",
                "content": {
                    "application/json": {
                        "schema": {"$ref": f"#/components/schemas/{response}"}
                    }
                },
            }
        }
        for code in (401, 403, 404, 409, 422):
            responses[str(code)] = {
                "description": "Contract error; see README for state and ownership rules",
                "content": {
                    "application/json": {
                        "schema": {"$ref": "#/components/schemas/ApiError"}
                    }
                },
            }
        op = {
            "operationId": name,
            "responses": responses,
            "security": [] if public else [{"bearerAuth": []}],
        }
        for parameter in ("session_id", "challenge_id"):
            if "{" + parameter + "}" in path:
                op.setdefault("parameters", []).append(
                    {
                        "name": parameter,
                        "in": "path",
                        "required": True,
                        "schema": {"type": "string", "format": "uuid"},
                    }
                )
        if request:
            op["requestBody"] = {
                "required": True,
                "content": {
                    "application/json": {
                        "schema": {"$ref": f"#/components/schemas/{request}"}
                    }
                },
            }
        paths.setdefault(path, {})[method] = op

    operation(
        "/api/v1/auth/register",
        "post",
        "register",
        "TokenResponse",
        201,
        "AuthRequest",
        True,
    )
    operation(
        "/api/v1/auth/token",
        "post",
        "login",
        "TokenResponse",
        request="AuthRequest",
        public=True,
    )
    operation(
        "/api/v1/workouts",
        "post",
        "createWorkout",
        "WorkoutSession",
        201,
        "CreateWorkout",
    )
    operation("/api/v1/workouts/{session_id}", "get", "getWorkout", "WorkoutSession")
    operation(
        "/api/v1/workouts/{session_id}/reps",
        "post",
        "submitRep",
        "RepReceipt",
        request="RepEvent",
    )
    operation(
        "/api/v1/workouts/{session_id}/complete",
        "post",
        "completeWorkout",
        "WorkoutSession",
    )
    operation(
        "/api/v1/challenges",
        "post",
        "createChallenge",
        "Challenge",
        201,
        "CreateChallenge",
    )
    operation("/api/v1/challenges/{challenge_id}", "get", "getChallenge", "Challenge")
    operation(
        "/api/v1/challenges/{challenge_id}/join", "post", "joinChallenge", "Challenge"
    )
    return {
        "openapi": "3.1.0",
        "info": {
            "title": "Competitive Fitness MVP (contract only)",
            "version": "1.0.0",
        },
        "paths": paths,
        "components": {
            "securitySchemes": {"bearerAuth": {"type": "http", "scheme": "bearer"}},
            "schemas": schemas("#/components/schemas/{model}"),
        },
    }


def artifacts():
    return {
        "schemas.json": {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "urn:competitive-fitness:contracts:1.0.0",
            "$defs": schemas("#/$defs/{model}"),
        },
        "openapi.json": openapi(),
    }


if __name__ == "__main__":
    for filename, value in artifacts().items():
        (ROOT / filename).write_text(
            json.dumps(value, indent=2) + "\n", encoding="utf-8"
        )
