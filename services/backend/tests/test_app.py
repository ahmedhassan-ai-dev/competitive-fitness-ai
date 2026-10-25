import secrets

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.config import Settings
from app.main import create_app, create_configured_app


def test_factory_isolation_and_injected_settings():
    settings = Settings(
        APP_ENV="test",
        DATABASE_URL="postgresql+psycopg://localhost/unused_test",
        JWT_SECRET=secrets.token_urlsafe(32),
        JWT_ISSUER="test",
        JWT_AUDIENCE="mobile",
    )
    first, second = create_app(settings), create_app()
    assert first is not second
    assert first.state.settings is settings
    assert second.state.settings is None

    @first.get("/only-first")
    def only_first():
        return {}

    with TestClient(first) as client:
        assert client.get("/api/v1/health").json() == {"status": "ok"}
        assert client.get("/only-first").status_code == 200
    with TestClient(second) as client:
        assert client.get("/only-first").status_code == 404
        assert client.get("/api/v1/health").status_code == 200


def test_scaffold_ignores_environment_and_exposes_no_auth(monkeypatch):
    monkeypatch.setenv("JWT_SECRET", "invalid")
    with TestClient(create_app()) as client:
        assert client.get("/api/v1/health").status_code == 200
        assert client.post("/api/v1/auth/register", json={}).status_code == 404


def test_configured_entry_requires_environment(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    with pytest.raises(ValidationError):
        create_configured_app()


def test_configured_entry_uses_environment(monkeypatch):
    for key, value in dict(
        APP_ENV="test",
        DATABASE_URL="postgresql+psycopg://localhost/unused",
        JWT_SECRET=secrets.token_urlsafe(32),
        JWT_ISSUER="test",
        JWT_AUDIENCE="mobile",
        JWT_ALGORITHM="HS256",
        ACCESS_TOKEN_TTL_SECONDS="900",
    ).items():
        monkeypatch.setenv(key, value)
    app = create_configured_app()
    with TestClient(app) as client:
        assert client.get("/api/v1/health").json() == {"status": "ok"}
    assert app.state.settings.access_token_ttl_seconds == 900
