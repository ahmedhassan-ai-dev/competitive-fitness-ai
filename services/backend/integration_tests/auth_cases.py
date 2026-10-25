"""Real HTTP/auth/database coverage, selected only by the disposable runner."""

import secrets
import time
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from typing import Annotated
from uuid import uuid4

import jwt
import pytest
from argon2 import PasswordHasher
from fastapi import Depends
from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app.auth import service
from app.auth.dependencies import get_current_user
from app.auth.models import User
from app.auth.security import issue_access_token
from app.config import Settings
from app.main import create_app
from packages.contracts.v1.models import ApiError, AuthRequest, TokenResponse


@pytest.fixture
def client(engine):
    # engine has already passed the runner's ownership/database checks.
    settings = Settings(
        APP_ENV="test",
        DATABASE_URL=engine.url.render_as_string(hide_password=False),
        JWT_SECRET=secrets.token_urlsafe(32),
        JWT_ISSUER="disposable-auth-test",
        JWT_AUDIENCE="disposable-mobile-test",
    )
    app = create_app(settings)

    @app.get("/test/protected", include_in_schema=False)
    def protected(user: Annotated[User, Depends(get_current_user)]):
        return {"user_id": str(user.user_id), "username": user.username}

    with TestClient(app, raise_server_exceptions=False) as result:
        yield result


def credentials():
    return {
        "username": "Auth_" + uuid4().hex[:20],
        "password": secrets.token_urlsafe(24),
    }


def bearer(response):
    return {"Authorization": "Bearer " + response.json()["access_token"]}


def test_register_login_and_protected_lookup(client, factory, caplog):
    body = credentials()
    response = client.post("/api/v1/auth/register", json=body)
    assert response.status_code == 201
    token = TokenResponse.model_validate(response.json())
    assert token.expires_in == 900 and token.token_type == "bearer"
    with factory() as session:
        stored = session.get(User, token.user_id)
        assert stored.username == body["username"]
        assert stored.password_hash.startswith("$argon2id$")
        assert client.app.state.passwords.verify(body["password"], stored.password_hash)
        assert set(User.__table__.columns.keys()) == {
            "user_id",
            "username",
            "password_hash",
            "created_at",
        }
    login = client.post("/api/v1/auth/token", json=body)
    assert login.status_code == 200
    assert TokenResponse.model_validate(login.json()).user_id == token.user_id
    authorized = client.get("/test/protected", headers=bearer(login))
    assert authorized.status_code == 200
    assert authorized.json() == {
        "user_id": str(token.user_id),
        "username": body["username"],
    }
    secrets_to_check = [
        body["password"],
        token.access_token,
        login.json()["access_token"],
        client.app.state.settings.jwt_secret.get_secret_value(),
    ]
    assert not any(value in caplog.text for value in secrets_to_check)


def test_duplicate_and_case_sensitive_usernames(client):
    body = credentials()
    first = client.post("/api/v1/auth/register", json=body)
    duplicate = client.post("/api/v1/auth/register", json=body)
    lower = {**body, "username": body["username"].lower()}
    assert client.post("/api/v1/auth/token", json=lower).status_code == 401
    second = client.post("/api/v1/auth/register", json=lower)
    assert first.status_code == second.status_code == 201
    assert first.json()["user_id"] != second.json()["user_id"]
    assert duplicate.status_code == 409
    assert duplicate.json() == {
        "code": "conflict",
        "message": "Request conflicts with the current resource state.",
    }


def test_wrong_password_and_unknown_user_have_same_error(client):
    body = credentials()
    assert client.post("/api/v1/auth/register", json=body).status_code == 201
    wrong = client.post(
        "/api/v1/auth/token", json={**body, "password": secrets.token_urlsafe(24)}
    )
    missing = client.post("/api/v1/auth/token", json=credentials())
    assert wrong.status_code == missing.status_code == 401
    assert (
        wrong.json()
        == missing.json()
        == {
            "code": "unauthorized",
            "message": "Authentication required or invalid credentials.",
        }
    )
    assert (
        wrong.headers["www-authenticate"]
        == missing.headers["www-authenticate"]
        == "Bearer"
    )
    assert client.post("/api/v1/auth/token", json=body).status_code == 200


@pytest.mark.parametrize(
    "authorization", [None, "", "Bearer", "Basic abc", "Bearer invalid", "Bearer a.b.c"]
)
def test_protected_route_rejects_invalid_authorization(client, authorization):
    response = client.get(
        "/test/protected",
        headers={} if authorization is None else {"Authorization": authorization},
    )
    assert response.status_code == 401
    assert ApiError.model_validate(response.json()).code == "unauthorized"
    assert response.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize(
    "mutation",
    [
        "expired",
        "signature",
        "issuer",
        "audience",
        "subject",
        "token_type",
        "algorithm",
    ],
)
def test_protected_route_rejects_invalid_tokens(client, mutation):
    settings = client.app.state.settings
    now = int(time.time())
    claims = {
        "sub": str(uuid4()),
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "iat": now,
        "exp": now + 900,
        "token_type": "access",
    }
    key, algorithm = settings.jwt_secret.get_secret_value(), "HS256"
    if mutation == "expired":
        claims.update(iat=now - 1000, exp=now - 100)
    elif mutation == "signature":
        key = secrets.token_urlsafe(32)
    elif mutation == "algorithm":
        algorithm = "HS512"
        key = secrets.token_urlsafe(64)
    else:
        claims[
            {
                "issuer": "iss",
                "audience": "aud",
                "subject": "sub",
                "token_type": "token_type",
            }[mutation]
        ] = "invalid"
    token = jwt.encode(claims, key, algorithm=algorithm, headers={"typ": "at+jwt"})
    response = client.get(
        "/test/protected", headers={"Authorization": "Bearer " + token}
    )
    assert response.status_code == 401
    assert response.json()["code"] == "unauthorized"


def test_unknown_and_deleted_token_subjects_are_unauthorized(client, factory):
    token = issue_access_token(uuid4(), client.app.state.settings)
    assert (
        client.get(
            "/test/protected", headers={"Authorization": "Bearer " + token.access_token}
        ).status_code
        == 401
    )
    created = client.post("/api/v1/auth/register", json=credentials())
    identity = TokenResponse.model_validate(created.json()).user_id
    with factory.begin() as session:
        session.delete(session.get(User, identity))
    assert client.get("/test/protected", headers=bearer(created)).status_code == 401


def test_duplicate_authorization_headers_rejected(client):
    created = client.post("/api/v1/auth/register", json=credentials())
    header = next(iter(bearer(created).items()))
    assert client.get("/test/protected", headers=[header, header]).status_code == 401


def test_concurrent_registration_returns_one_token_and_one_conflict(
    client, factory, monkeypatch
):
    body = credentials()
    barrier = Barrier(2)
    original = client.app.state.passwords.hash

    def synchronized(password):
        encoded = original(password)
        barrier.wait(timeout=10)
        return encoded

    monkeypatch.setattr(client.app.state.passwords, "hash", synchronized)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(
            pool.map(
                lambda _: client.post("/api/v1/auth/register", json=body), range(2)
            )
        )
    assert sorted(response.status_code for response in results) == [201, 409]
    with factory() as session:
        assert (
            session.scalar(
                select(func.count())
                .select_from(User)
                .where(User.username == body["username"])
            )
            == 1
        )
    accepted = next(response for response in results if response.status_code == 201)
    assert client.get("/test/protected", headers=bearer(accepted)).status_code == 200


def test_token_issuance_failure_rolls_back_registration(client, factory, monkeypatch):
    body = credentials()
    original = service.issue_access_token

    def fail(*args):
        raise RuntimeError("synthetic issuance failure")

    monkeypatch.setattr(service, "issue_access_token", fail)
    response = client.post("/api/v1/auth/register", json=body)
    assert response.status_code == 500 and response.text == "Internal Server Error"
    with factory() as session:
        assert (
            session.scalar(select(User).where(User.username == body["username"]))
            is None
        )
    monkeypatch.setattr(service, "issue_access_token", original)
    assert client.post("/api/v1/auth/register", json=body).status_code == 201


def test_conflict_rolls_back_and_same_session_can_be_reused(client, factory):
    from fastapi import HTTPException

    body = credentials()
    assert client.post("/api/v1/auth/register", json=body).status_code == 201
    with factory() as session:
        with pytest.raises(HTTPException) as error:
            service.register(
                AuthRequest(**body),
                session,
                client.app.state.settings,
                client.app.state.passwords,
            )
        assert error.value.status_code == 409 and not session.in_transaction()
        response = service.register(
            AuthRequest(**credentials()),
            session,
            client.app.state.settings,
            client.app.state.passwords,
        )
        assert response.user_id is not None and not session.in_transaction()


def test_login_rehashes_old_parameters(client, factory):
    body = credentials()
    old_hash = PasswordHasher(time_cost=1, memory_cost=8192, parallelism=1).hash(
        body["password"]
    )
    with factory.begin() as session:
        session.add(User(username=body["username"], password_hash=old_hash))
    assert client.post("/api/v1/auth/token", json=body).status_code == 200
    with factory() as session:
        stored = session.scalar(select(User).where(User.username == body["username"]))
        assert not client.app.state.passwords.needs_rehash(stored.password_hash)
        assert client.app.state.passwords.verify(body["password"], stored.password_hash)


def test_password_unicode_and_whitespace_preserved(client):
    body = {**credentials(), "password": "  synthetic-密碼-🏋️  "}
    assert client.post("/api/v1/auth/register", json=body).status_code == 201
    assert client.post("/api/v1/auth/token", json=body).status_code == 200
    assert (
        client.post(
            "/api/v1/auth/token", json={**body, "password": body["password"].strip()}
        ).status_code
        == 401
    )
