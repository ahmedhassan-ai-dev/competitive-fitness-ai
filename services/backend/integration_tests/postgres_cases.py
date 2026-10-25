"""Explicitly selected by the runner; excluded from default pytest discovery."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from threading import Barrier
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from sqlalchemy import inspect, select, text
from sqlalchemy.exc import DBAPIError, IntegrityError

from app.auth.models import User
from app.db import get_session

# Deliberately not a real password hash: this checkpoint tests storage constraints.
HASH = "$argon2id$synthetic-storage-fixture"


def user(**values):
    return User(
        **{"username": "u_" + uuid4().hex[:24], "password_hash": HASH, **values}
    )


def test_migrated_schema_matches_model(engine):
    inspector = inspect(engine)
    columns = {column["name"]: column for column in inspector.get_columns("users")}
    assert set(columns) == {"user_id", "username", "password_hash", "created_at"}
    assert all(not column["nullable"] for column in columns.values())
    assert str(columns["user_id"]["type"]) == "UUID"
    assert columns["user_id"]["default"] is None
    assert columns["username"]["type"].length == 32
    assert str(columns["password_hash"]["type"]) == "TEXT"
    assert columns["created_at"]["type"].timezone is True
    assert columns["created_at"]["default"] == "now()"
    assert inspector.get_pk_constraint("users")["constrained_columns"] == ["user_id"]
    assert inspector.get_unique_constraints("users")[0]["name"] == "uq_users_username"
    assert {c["name"] for c in inspector.get_check_constraints("users")} == {
        "ck_users_username_format",
        "ck_users_password_hash_argon2id",
    }
    with engine.connect() as connection:
        assert (
            connection.scalar(
                text(
                    "SELECT collation_name FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='username'"
                )
            )
            == "C"
        )


def test_uuid_defaults_and_committed_round_trip(factory):
    with factory() as session:
        first, second = user(), user()
        assert first.user_id is None
        session.add_all([first, second])
        session.commit()
        assert isinstance(first.user_id, UUID) and first.user_id.version == 4
        assert first.user_id != second.user_id
        identity = first.user_id
    with factory() as session:
        assert session.get(User, identity).user_id == identity


def test_duplicate_username_rejected_and_session_recovers(factory):
    name = "u_" + uuid4().hex[:24]
    with factory() as session:
        session.add(user(username=name))
        session.commit()
        session.add(user(username=name))
        with pytest.raises(IntegrityError) as error:
            session.commit()
        assert error.value.orig.diag.constraint_name == "uq_users_username"
        session.rollback()
        session.add(user())
        session.commit()


def test_concurrent_same_username_allows_exactly_one_commit(factory):
    barrier = Barrier(2)
    name = "race_" + uuid4().hex[:20]

    def insert():
        with factory() as session:
            session.execute(text("SET LOCAL statement_timeout = '5s'"))
            session.add(user(username=name))
            barrier.wait(timeout=5)
            try:
                session.commit()
                return "accepted"
            except IntegrityError as error:
                session.rollback()
                assert error.orig.diag.constraint_name == "uq_users_username"
                return "duplicate"

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: insert(), range(2)))
    assert sorted(results) == ["accepted", "duplicate"]


def test_username_uniqueness_is_case_sensitive(factory):
    name = "Case_" + uuid4().hex[:20]
    with factory() as session:
        session.add_all([user(username=name), user(username=name.lower())])
        session.commit()
        assert (
            len(
                session.scalars(
                    select(User).where(User.username.in_([name, name.lower()]))
                ).all()
            )
            == 2
        )


@pytest.mark.parametrize("name", ["ab", "a" * 33, "with space", "name-é", "name\n"])
def test_username_format_rejected(factory, name):
    with factory() as session:
        session.add(user(username=name))
        with pytest.raises(DBAPIError) as error:
            session.flush()
        assert error.value.orig.sqlstate in {"23514", "22001"}
        session.rollback()


def test_wrong_hash_scheme_rejected(factory):
    with factory() as session:
        session.add(user(password_hash="not-an-argon2id-hash"))
        with pytest.raises(IntegrityError) as error:
            session.flush()
        assert (
            error.value.orig.diag.constraint_name == "ck_users_password_hash_argon2id"
        )


@pytest.mark.parametrize("value,code", [(None, "23502"), ("not-a-uuid", "22P02")])
def test_direct_sql_requires_valid_uuid(engine, value, code):
    with engine.connect() as connection:
        with pytest.raises(DBAPIError) as error:
            connection.execute(
                text(
                    "INSERT INTO users(user_id, username, password_hash) VALUES (:id, :name, :hash)"
                ),
                {"id": value, "name": "u_" + uuid4().hex[:24], "hash": HASH},
            )
        assert error.value.orig.sqlstate == code


def test_duplicate_uuid_primary_key_rejected(factory):
    identity = uuid4()
    with factory() as session:
        session.add(user(user_id=identity))
        session.commit()
        session.add(user(user_id=identity))
        with pytest.raises(IntegrityError) as error:
            session.flush()
        assert error.value.orig.diag.constraint_name == "users_pkey"


def test_database_time_default_is_utc_transaction_start(factory):
    with factory() as session:
        started = session.scalar(text("SELECT transaction_timestamp()"))
        assert session.scalar(text("SHOW TIME ZONE")) == "UTC"
        first, second = user(), user()
        session.add(first)
        session.flush()
        session.add(second)
        session.flush()
        assert first.created_at == second.created_at == started
        assert first.created_at.utcoffset() == timedelta(0)


def test_explicit_offset_timestamp_round_trips_as_same_instant(factory):
    when = datetime(2026, 1, 2, 12, 30, tzinfo=timezone(timedelta(hours=2)))
    with factory() as session:
        item = user(created_at=when)
        session.add(item)
        session.commit()
        identity = item.user_id
    with factory() as session:
        stored = session.get(User, identity).created_at
        assert stored == when and stored.utcoffset() == timedelta(0)


@pytest.mark.parametrize("exit_mode", ["normal", "error", "cancel"])
def test_request_session_cleanup_rolls_back_flushed_rows(factory, exit_mode):
    request = SimpleNamespace(
        app=SimpleNamespace(state=SimpleNamespace(session_factory=factory))
    )
    dependency = get_session(request)
    session = next(dependency)
    item = user()
    session.add(item)
    session.flush()
    identity = item.user_id
    if exit_mode == "normal":
        with pytest.raises(StopIteration):
            next(dependency)
    elif exit_mode == "error":
        with pytest.raises(ValueError):
            dependency.throw(ValueError("synthetic request failure"))
    else:
        dependency.close()
    with factory() as independent:
        assert independent.get(User, identity) is None


def test_runtime_role_cannot_create_tables(engine):
    with engine.connect() as connection:
        role = connection.execute(
            text(
                "SELECT rolsuper, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname=current_user"
            )
        ).one()
        assert role == (False, False, False)
        with pytest.raises(DBAPIError) as error:
            connection.execute(text("CREATE TABLE forbidden_runtime_ddl (id integer)"))
        assert error.value.orig.sqlstate == "42501"
