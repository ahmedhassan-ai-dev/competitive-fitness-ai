"""Password and access-token primitives. Never log inputs, hashes or tokens."""

import secrets
from datetime import datetime, timezone
from uuid import UUID

import jwt
from argon2 import PasswordHasher, Type
from argon2.exceptions import InvalidHashError, VerificationError

from app.config import Settings
from packages.contracts.v1.models import TokenResponse


class Passwords:
    def __init__(self):
        self.hasher = PasswordHasher(
            time_cost=3,
            memory_cost=65536,
            parallelism=4,
            hash_len=32,
            salt_len=16,
            type=Type.ID,
        )
        self._dummy_hash = self.hash(secrets.token_urlsafe(32))

    def hash(self, password: str) -> str:
        return self.hasher.hash(password)

    def verify(self, password: str, encoded: str | None) -> bool:
        candidate = (
            encoded
            if encoded and encoded.startswith("$argon2id$")
            else self._dummy_hash
        )
        try:
            valid = self.hasher.verify(candidate, password)
        except (VerificationError, InvalidHashError):
            return False
        return bool(encoded and candidate == encoded and valid)

    def needs_rehash(self, encoded: str) -> bool:
        return self.hasher.check_needs_rehash(encoded)


class InvalidAccessToken(ValueError):
    """Safe message only; the rejected token must not be included."""


def issue_access_token(user_id: UUID, settings: Settings) -> TokenResponse:
    issued = int(datetime.now(timezone.utc).timestamp())
    token = jwt.encode(
        {
            "sub": str(user_id),
            "iss": settings.jwt_issuer,
            "aud": settings.jwt_audience,
            "iat": issued,
            "exp": issued + settings.access_token_ttl_seconds,
            "token_type": "access",
        },
        settings.jwt_secret.get_secret_value(),
        algorithm="HS256",
        headers={"typ": "at+jwt"},
    )
    return TokenResponse(
        access_token=token, token_type="bearer", expires_in=900, user_id=user_id
    )


def validate_access_token(token: str, settings: Settings) -> UUID:
    try:
        decoded = jwt.decode_complete(
            token,
            settings.jwt_secret.get_secret_value(),
            algorithms=["HS256"],
            issuer=settings.jwt_issuer,
            audience=settings.jwt_audience,
            leeway=0,
            options={
                "require": ["sub", "iss", "aud", "iat", "exp", "token_type"],
                "strict_aud": True,
            },
        )
        claims, header = decoded["payload"], decoded["header"]
        if (
            header.get("typ") != "at+jwt"
            or header.get("alg") != "HS256"
            or header.get("crit")
            or claims["token_type"] != "access"
            or type(claims["iat"]) is not int
            or type(claims["exp"]) is not int
            or claims["exp"] - claims["iat"] != 900
        ):
            raise ValueError
        identity = UUID(claims["sub"])
        if str(identity) != claims["sub"] or identity.int == 0:
            raise ValueError
        return identity
    except (jwt.InvalidTokenError, ValueError, TypeError, OverflowError):
        raise InvalidAccessToken("Invalid access token.") from None
