import json
import secrets
from pathlib import Path
from unittest.mock import Mock
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.auth import service
from app.config import Settings
from app.db import get_session
from app.main import create_app
from packages.contracts.v1.models import TokenResponse


@pytest.fixture
def app():
    settings = Settings(
        APP_ENV="test",
        DATABASE_URL="postgresql+psycopg://localhost/never_connect",
        JWT_SECRET=secrets.token_urlsafe(32),
        JWT_ISSUER="test",
        JWT_AUDIENCE="mobile",
    )
    app = create_app(settings)
    app.dependency_overrides[get_session] = lambda: Mock()
    return app


def test_auth_paths_operations_and_schemas_match_approved_openapi(app):
    contract = json.loads(
        (
            Path(__file__).resolve().parents[3] / "packages/contracts/v1/openapi.json"
        ).read_text()
    )
    schema = app.openapi()
    for path in ("/api/v1/auth/register", "/api/v1/auth/token"):
        actual, expected = (
            schema["paths"][path]["post"],
            contract["paths"][path]["post"],
        )
        assert actual["operationId"] == expected["operationId"]
        assert actual["requestBody"] == expected["requestBody"]
        assert actual.get("security", []) == []
        assert actual["responses"].keys() == expected["responses"].keys()
        for status in expected["responses"]:
            assert (
                actual["responses"][status]["content"]
                == expected["responses"][status]["content"]
            )
    for name in ("AuthRequest", "TokenResponse", "ApiError"):
        assert (
            schema["components"]["schemas"][name]
            == contract["components"]["schemas"][name]
        )
    assert set(schema["paths"]) == {
        "/api/v1/health",
        "/api/v1/auth/register",
        "/api/v1/auth/token",
    }


@pytest.mark.parametrize("route,status", [("register", 201), ("token", 200)])
def test_routes_return_exact_envelope_and_disable_caching(
    app, monkeypatch, route, status
):
    result = TokenResponse(
        access_token="synthetic-contract-token",
        token_type="bearer",
        expires_in=900,
        user_id=uuid4(),
    )
    monkeypatch.setattr(
        service,
        "register" if route == "register" else "login",
        Mock(return_value=result),
    )
    with TestClient(app) as client:
        response = client.post(
            f"/api/v1/auth/{route}",
            json={"username": "Valid_Name", "password": "synthetic-password"},
        )
    assert response.status_code == status
    assert response.json() == result.model_dump(mode="json")
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["pragma"] == "no-cache"


@pytest.mark.parametrize("route", ["register", "token"])
@pytest.mark.parametrize(
    "body",
    [
        {"username": "ab", "password": "synthetic-password"},
        {"username": "Valid_Name", "password": "short"},
        {"username": "Valid_Name", "password": "x" * 129},
        {
            "username": "Valid_Name",
            "password": "synthetic-password",
            "user_id": "extra",
        },
        {"username": "Valid_Name", "password": 123456789012},
    ],
)
def test_invalid_auth_requests_do_not_reach_service(app, monkeypatch, route, body):
    operation = Mock(side_effect=AssertionError("Invalid request reached auth service"))
    monkeypatch.setattr(
        service, "register" if route == "register" else "login", operation
    )
    with TestClient(app) as client:
        response = client.post(f"/api/v1/auth/{route}", json=body)
    assert response.status_code == 422
    assert response.json() == {
        "code": "validation_error",
        "message": "Request validation failed.",
    }
    operation.assert_not_called()
