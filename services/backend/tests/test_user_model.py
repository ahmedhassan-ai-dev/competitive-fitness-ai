from uuid import UUID

from sqlalchemy import CheckConstraint, UniqueConstraint
from sqlalchemy.dialects import postgresql
from sqlalchemy.schema import CreateTable

from app.auth.models import User


def test_user_columns_and_defaults():
    table = User.__table__
    assert set(table.c.keys()) == {"user_id", "username", "password_hash", "created_at"}
    assert all(not column.nullable for column in table.c)
    assert list(table.primary_key.columns.keys()) == ["user_id"]
    assert table.c.user_id.type.as_uuid
    first = table.c.user_id.default.arg(None)
    assert isinstance(first, UUID) and first.version == 4
    assert first != table.c.user_id.default.arg(None)
    assert table.c.user_id.server_default is None
    assert table.c.username.type.length == 32
    assert table.c.username.type.collation == "C"
    assert table.c.created_at.type.timezone is True
    assert str(table.c.created_at.server_default.arg) == "now()"


def test_named_integrity_constraints():
    constraints = User.__table__.constraints
    unique = [c for c in constraints if isinstance(c, UniqueConstraint)]
    assert [(c.name, list(c.columns.keys())) for c in unique] == [
        ("uq_users_username", ["username"])
    ]
    checks = {
        c.name: str(c.sqltext) for c in constraints if isinstance(c, CheckConstraint)
    }
    assert checks == {
        "ck_users_username_format": "username ~ '^[A-Za-z0-9_]{3,32}$'",
        "ck_users_password_hash_argon2id": "password_hash LIKE '$argon2id$%'",
    }


def test_postgresql_ddl_and_safe_representation():
    ddl = str(CreateTable(User.__table__).compile(dialect=postgresql.dialect()))
    assert 'username VARCHAR(32) COLLATE "C" NOT NULL' in ddl
    assert "TIMESTAMP WITH TIME ZONE" in ddl
    assert "user_id UUID NOT NULL" in ddl
    user = User(username="example", password_hash="$argon2id$metadata-only")
    assert "metadata-only" not in repr(user)
