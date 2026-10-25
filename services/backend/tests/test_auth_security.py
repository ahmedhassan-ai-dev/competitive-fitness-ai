import secrets
import time
from unittest.mock import Mock
from uuid import uuid4

import jwt
import pytest
from argon2 import Type, extract_parameters

from app.auth.security import (
    InvalidAccessToken,
    Passwords,
    issue_access_token,
    validate_access_token,
)
from app.config import Settings


@pytest.fixture
def settings():
    return Settings(
        APP_ENV="test",
        DATABASE_URL="postgresql+psycopg://localhost/never_connect",
        JWT_SECRET=secrets.token_urlsafe(32),
        JWT_ISSUER="fitness-test",
        JWT_AUDIENCE="mobile-test",
    )


@pytest.fixture(scope="module")
def passwords():
    return Passwords()


def test_argon2id_salts_verification_and_parameters(passwords):
    password = secrets.token_urlsafe(16)
    first, second = passwords.hash(password), passwords.hash(password)
    assert first != second
    parameters = extract_parameters(first)
    assert parameters.type is Type.ID
    assert (parameters.memory_cost, parameters.time_cost, parameters.parallelism) == (
        65536,
        3,
        4,
    )
    assert passwords.verify(password, first)
    assert not passwords.verify(password + "wrong", first)
    assert not passwords.needs_rehash(first)


@pytest.mark.parametrize("encoded", [None, "$argon2id$broken", "$argon2i$unsupported"])
def test_missing_and_invalid_hashes_fail_closed(passwords, encoded):
    assert not passwords.verify("synthetic-password", encoded)


def test_missing_user_still_runs_argon2_verification(passwords, monkeypatch):
    verify = Mock(return_value=True)
    monkeypatch.setattr(passwords, "hasher", Mock(verify=verify))
    assert not passwords.verify("synthetic-password", None)
    verify.assert_called_once_with(passwords._dummy_hash, "synthetic-password")


def test_issued_token_has_minimal_claims_and_fixed_lifetime(settings):
    identity = uuid4()
    response = issue_access_token(identity, settings)
    assert response.token_type == "bearer" and response.expires_in == 900
    assert (
        response.user_id
        == validate_access_token(response.access_token, settings)
        == identity
    )
    decoded = jwt.decode_complete(
        response.access_token,
        settings.jwt_secret.get_secret_value(),
        algorithms=["HS256"],
        issuer=settings.jwt_issuer,
        audience=settings.jwt_audience,
    )
    claims = decoded["payload"]
    assert set(claims) == {"sub", "iss", "aud", "iat", "exp", "token_type"}
    assert claims["exp"] - claims["iat"] == 900
    assert decoded["header"] == {"alg": "HS256", "typ": "at+jwt"}


@pytest.mark.parametrize(
    "mutation",
    [
        "expired",
        "signature",
        "audience",
        "issuer",
        "audience_list",
        "algorithm",
        "unsigned",
        "header_type",
        "token_type",
        "subject",
        "nil_subject",
        "numeric_subject",
        "future",
        "iat_string",
        "exp_string",
        "iat_boolean",
        "exp_boolean",
        "lifetime",
        "critical_header",
        "missing_sub",
        "missing_iss",
        "missing_aud",
        "missing_iat",
        "missing_exp",
        "missing_token_type",
    ],
)
def test_invalid_signed_tokens_rejected(settings, mutation):
    now = int(time.time())
    claims = {
        "sub": str(uuid4()),
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "iat": now,
        "exp": now + 900,
        "token_type": "access",
    }
    headers = {"typ": "at+jwt"}
    key, algorithm = settings.jwt_secret.get_secret_value(), "HS256"
    if mutation.startswith("missing_"):
        del claims[mutation.removeprefix("missing_")]
    elif mutation == "expired":
        claims.update(iat=now - 901, exp=now - 1)
    elif mutation == "signature":
        key = secrets.token_urlsafe(32)
    elif mutation == "audience":
        claims["aud"] = "another-app"
    elif mutation == "issuer":
        claims["iss"] = "another-issuer"
    elif mutation == "audience_list":
        claims["aud"] = [settings.jwt_audience]
    elif mutation == "algorithm":
        algorithm = "HS384"
        key = secrets.token_urlsafe(64)
    elif mutation == "unsigned":
        algorithm, key = "none", None
    elif mutation == "header_type":
        headers["typ"] = "JWT"
    elif mutation == "token_type":
        claims["token_type"] = "refresh"
    elif mutation == "subject":
        claims["sub"] = "not-a-uuid"
    elif mutation == "nil_subject":
        claims["sub"] = "00000000-0000-0000-0000-000000000000"
    elif mutation == "numeric_subject":
        claims["sub"] = 123
    elif mutation == "future":
        claims.update(iat=now + 60, exp=now + 960)
    elif mutation in {"iat_string", "exp_string"}:
        claim = mutation[:3]
        claims[claim] = str(claims[claim])
    elif mutation in {"iat_boolean", "exp_boolean"}:
        claims[mutation[:3]] = True
    elif mutation == "lifetime":
        claims["exp"] += 1
    elif mutation == "critical_header":
        headers["crit"] = ["unsupported"]
    token = jwt.encode(claims, key, algorithm=algorithm, headers=headers)
    with pytest.raises(InvalidAccessToken, match="^Invalid access token.$"):
        validate_access_token(token, settings)


@pytest.mark.parametrize(
    "token", ["", "not-a-token", "a.b.c", "{}.{}.{}", "a.b", "." * 20]
)
def test_malformed_tokens_rejected(settings, token):
    with pytest.raises(InvalidAccessToken):
        validate_access_token(token, settings)
