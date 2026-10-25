import runpy
from contextlib import nullcontext
from pathlib import Path
from unittest.mock import Mock

import pytest
import sqlalchemy as sa
from alembic import context
from alembic.config import Config
from alembic.script import ScriptDirectory
from pydantic import ValidationError
from sqlalchemy.dialects import postgresql
from sqlalchemy.schema import CreateTable

from app.auth.models import User
from app.config import DatabaseSettings

BACKEND = Path(__file__).resolve().parents[1]


def revision():
    scripts = ScriptDirectory.from_config(Config(str(BACKEND / "alembic.ini")))
    assert scripts.get_heads() == ["0001_create_users"]
    result = scripts.get_revision("head")
    assert result.down_revision is None
    return result.module


def test_initial_migration_matches_model_metadata(monkeypatch):
    migration = revision()
    captured = []

    def record(name, *columns, **kwargs):
        captured.append(sa.Table(name, sa.MetaData(), *columns, **kwargs))

    # Record operations and compile DDL; never run an Alembic migration or SQL.
    monkeypatch.setattr(migration.op, "create_table", record)
    migration.upgrade()
    assert len(captured) == 1
    dialect = postgresql.dialect()
    assert str(CreateTable(captured[0]).compile(dialect=dialect)) == str(
        CreateTable(User.__table__).compile(dialect=dialect)
    )


def test_downgrade_only_targets_users(monkeypatch):
    migration = revision()
    drop = Mock()
    monkeypatch.setattr(migration.op, "drop_table", drop)
    migration.downgrade()
    drop.assert_called_once_with("users")


def test_alembic_only_requires_database_environment(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://localhost/never_connect")
    for key in ("JWT_SECRET", "JWT_ISSUER", "JWT_AUDIENCE", "APP_ENV"):
        monkeypatch.delenv(key, raising=False)
    assert DatabaseSettings().database_url.get_secret_value().endswith("never_connect")


def test_missing_database_environment_fails(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    with pytest.raises(ValidationError):
        DatabaseSettings()


def test_offline_environment_uses_postgresql_without_engine(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://localhost/never_connect")
    forbidden = Mock(side_effect=AssertionError("No engine allowed"))
    monkeypatch.setattr(sa, "create_engine", forbidden)
    configure = Mock()
    monkeypatch.setattr(context, "is_offline_mode", lambda: True)
    monkeypatch.setattr(context, "configure", configure)
    monkeypatch.setattr(context, "begin_transaction", nullcontext)
    monkeypatch.setattr(context, "run_migrations", Mock())
    runpy.run_path(str(BACKEND / "alembic/env.py"))
    assert configure.call_args.kwargs["dialect_name"] == "postgresql"
    assert configure.call_args.kwargs["target_metadata"] is User.metadata
    assert "url" not in configure.call_args.kwargs
    forbidden.assert_not_called()


def test_online_environment_requires_explicit_review_opt_in(monkeypatch):
    forbidden = Mock(side_effect=AssertionError("No engine allowed"))
    monkeypatch.setattr(sa, "create_engine", forbidden)
    monkeypatch.setattr(context, "is_offline_mode", lambda: False)
    monkeypatch.setattr(context, "get_x_argument", lambda **kwargs: {})
    with pytest.raises(RuntimeError, match="require review"):
        runpy.run_path(str(BACKEND / "alembic/env.py"))
    forbidden.assert_not_called()
