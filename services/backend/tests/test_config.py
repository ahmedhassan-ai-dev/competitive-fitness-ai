import secrets

import pytest
from pydantic import ValidationError

from app.config import Settings

CONFIG_KEYS = (
    "APP_ENV",
    "DATABASE_URL",
    "JWT_SECRET",
    "JWT_ISSUER",
    "JWT_AUDIENCE",
    "JWT_ALGORITHM",
    "ACCESS_TOKEN_TTL_SECONDS",
)


@pytest.fixture(autouse=True)
def clean_environment(monkeypatch):
    for key in CONFIG_KEYS:
        monkeypatch.delenv(key, raising=False)


def values():
    return dict(
        APP_ENV="test",
        DATABASE_URL="postgresql+psycopg://localhost/unused_test",
        JWT_SECRET=secrets.token_urlsafe(32),
        JWT_ISSUER="fitness-test",
        JWT_AUDIENCE="fitness-mobile-test",
    )


def test_environment_configuration(monkeypatch):
    config = values()
    for key, value in config.items():
        monkeypatch.setenv(key, value)
    monkeypatch.setenv("ACCESS_TOKEN_TTL_SECONDS", "900")
    result = Settings()
    assert result.app_env == "test"
    assert result.access_token_ttl_seconds == 900
    assert result.jwt_algorithm == "HS256"
    assert result.jwt_secret.get_secret_value() == config["JWT_SECRET"]
    assert config["JWT_SECRET"] not in repr(result)
    assert config["DATABASE_URL"] not in repr(result)


@pytest.mark.parametrize(
    "missing", ["APP_ENV", "DATABASE_URL", "JWT_SECRET", "JWT_ISSUER", "JWT_AUDIENCE"]
)
def test_required_configuration(missing):
    config = values()
    del config[missing]
    with pytest.raises(ValidationError):
        Settings(**config)


@pytest.mark.parametrize(
    "key,value",
    [
        ("APP_ENV", "unknown"),
        ("DATABASE_URL", "sqlite:///local.db"),
        ("DATABASE_URL", "postgresql+asyncpg://localhost/db"),
        ("DATABASE_URL", "postgresql+psycopg://localhost"),
        ("DATABASE_URL", "postgresql+psycopg://localhost:bad/db"),
        ("DATABASE_URL", "postgresql+psycopg://localhost:0/db"),
        ("DATABASE_URL", "postgresql+psycopg:///db"),
        ("JWT_SECRET", "short"),
        ("JWT_SECRET", "a" * 64),
        ("JWT_ISSUER", "  "),
        ("JWT_AUDIENCE", " mobile"),
        ("JWT_ALGORITHM", "none"),
        ("ACCESS_TOKEN_TTL_SECONDS", 0),
        ("ACCESS_TOKEN_TTL_SECONDS", 901),
    ],
)
def test_invalid_settings(key, value):
    config = {**values(), key: value}
    with pytest.raises(ValidationError) as error:
        Settings(**config)
    assert "input_value=" not in str(error.value)
    assert "input_type=" not in str(error.value)


def test_dotenv_is_not_discovered(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".env").write_text("\n".join(f"{k}={v}" for k, v in values().items()))
    with pytest.raises(ValidationError):
        Settings()


def test_database_password_is_redacted():
    config = values()
    password = secrets.token_urlsafe(20)
    config["DATABASE_URL"] = f"postgresql+psycopg://user:{password}@localhost/test"
    settings = Settings(**config)
    assert password not in repr(settings)
    assert config["JWT_SECRET"] not in settings.model_dump_json()
