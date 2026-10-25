import secrets
from types import SimpleNamespace
from unittest.mock import Mock

import psycopg
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.auth.models import User
from app.config import DatabaseSettings, Settings
from app.db import create_database_engine, create_session_factory, get_session
from app.main import create_app


@pytest.fixture(autouse=True)
def forbid_database_connections(monkeypatch):
    def forbidden(*args, **kwargs):
        pytest.fail("Unit tests must not open PostgreSQL connections")

    monkeypatch.setattr(psycopg, "connect", forbidden)


def test_lazy_engine_and_distinct_sessions():
    engine = create_database_engine(
        DatabaseSettings(DATABASE_URL="postgresql+psycopg://localhost/never_connect")
    )
    try:
        assert engine.dialect.name == "postgresql"
        assert engine.dialect.driver == "psycopg"
        assert engine.echo is False and engine.hide_parameters is True
        factory = create_session_factory(engine)
        with factory() as first, factory() as second:
            assert first is not second
            assert first.bind is engine
            assert not first.autoflush and not first.expire_on_commit
            assert not first.in_transaction()
    finally:
        engine.dispose()


@pytest.mark.parametrize("exit_mode", ["normal", "error", "cancel"])
def test_dependency_closes_uncommitted_sessions(exit_mode, monkeypatch):
    session = Session()
    commit = Mock(side_effect=AssertionError("Dependency must not commit"))
    monkeypatch.setattr(session, "commit", commit)
    request = SimpleNamespace(
        app=SimpleNamespace(state=SimpleNamespace(session_factory=lambda: session))
    )
    dependency = get_session(request)
    assert next(dependency) is session
    pending = User(username="example", password_hash="$argon2id$metadata-only")
    session.add(pending)
    assert session.in_transaction() and pending in session
    if exit_mode == "normal":
        with pytest.raises(StopIteration):
            next(dependency)
    elif exit_mode == "error":
        with pytest.raises(ValueError, match="service failure"):
            dependency.throw(ValueError("service failure"))
    else:
        dependency.close()
    assert not session.in_transaction()
    assert pending not in session
    commit.assert_not_called()


def test_unconfigured_session_dependency_fails_closed():
    request = SimpleNamespace(app=create_app())
    with pytest.raises(RuntimeError, match="configured application lifespan"):
        next(get_session(request))


def test_app_lifespan_disposes_engine_and_keeps_health_connection_free(monkeypatch):
    settings = Settings(
        APP_ENV="test",
        DATABASE_URL="postgresql+psycopg://localhost/never_connect",
        JWT_SECRET=secrets.token_urlsafe(32),
        JWT_ISSUER="test",
        JWT_AUDIENCE="test",
    )
    engine = create_database_engine(settings)
    dispose = Mock(wraps=engine.dispose)
    monkeypatch.setattr(engine, "dispose", dispose)
    monkeypatch.setattr("app.main.create_database_engine", lambda _: engine)
    app = create_app(settings)
    assert app.state.session_factory is None
    with TestClient(app) as client:
        assert app.state.session_factory is not None
        assert client.get("/api/v1/health").json() == {"status": "ok"}
    dispose.assert_called_once()
    assert app.state.session_factory is None


def test_lifespan_disposes_engine_when_session_factory_setup_fails(monkeypatch):
    engine = Mock()
    monkeypatch.setattr("app.main.create_database_engine", lambda _: engine)

    def fail(_):
        raise RuntimeError("session setup failed")

    monkeypatch.setattr("app.main.create_session_factory", fail)
    # Explicit validated database settings suffice to exercise resource cleanup.
    settings = Settings(
        APP_ENV="test",
        DATABASE_URL="postgresql+psycopg://localhost/never_connect",
        JWT_SECRET=secrets.token_urlsafe(32),
        JWT_ISSUER="test",
        JWT_AUDIENCE="test",
    )
    with pytest.raises(RuntimeError, match="session setup failed"):
        with TestClient(create_app(settings)):
            pass
    engine.dispose.assert_called_once()
