"""Environment-only configuration; construction does not connect to a database."""

from typing import Literal
from urllib.parse import urlsplit

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=None,
        case_sensitive=True,
        extra="forbid",
        hide_input_in_errors=True,
        frozen=True,
        populate_by_name=True,
    )

    app_env: Literal["development", "test", "production"] = Field(
        validation_alias="APP_ENV"
    )
    database_url: SecretStr = Field(validation_alias="DATABASE_URL")
    jwt_secret: SecretStr = Field(validation_alias="JWT_SECRET")
    jwt_issuer: str = Field(min_length=1, max_length=200, validation_alias="JWT_ISSUER")
    jwt_audience: str = Field(
        min_length=1, max_length=200, validation_alias="JWT_AUDIENCE"
    )
    jwt_algorithm: Literal["HS256"] = Field(
        default="HS256", validation_alias="JWT_ALGORITHM"
    )
    access_token_ttl_seconds: int = Field(
        default=900, ge=900, le=900, validation_alias="ACCESS_TOKEN_TTL_SECONDS"
    )

    @field_validator("database_url")
    @classmethod
    def postgres_url(cls, value: SecretStr) -> SecretStr:
        try:
            parsed = urlsplit(value.get_secret_value())
            port = parsed.port
            valid = (
                parsed.scheme == "postgresql+psycopg"
                and parsed.hostname
                and parsed.path not in ("", "/")
                and not parsed.fragment
                and (port is None or 1 <= port <= 65535)
            )
        except ValueError:
            valid = False
        if not valid:
            raise ValueError(
                "DATABASE_URL must be a PostgreSQL psycopg URL with host and database"
            )
        return value

    @field_validator("jwt_secret")
    @classmethod
    def signing_secret(cls, value: SecretStr) -> SecretStr:
        secret = value.get_secret_value()
        # Length/distinctness rejects trivial mistakes, not a proof of entropy.
        if len(secret.encode("utf-8")) < 32 or len(set(secret)) < 8:
            raise ValueError(
                "JWT_SECRET must be independently generated with at least 32 random bytes"
            )
        return value

    @field_validator("jwt_issuer", "jwt_audience")
    @classmethod
    def nonblank(cls, value: str) -> str:
        if not value.strip() or value != value.strip():
            raise ValueError(
                "issuer and audience must be nonblank without surrounding whitespace"
            )
        return value
