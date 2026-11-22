"""Real route tests: owner permissions, idempotence, ranking, and submissions."""

import secrets
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.auth.dependencies import get_current_user
from app.config import Settings
from app.db import Base, get_session
from app.main import create_app
from app.rooms.models import ChallengeRoom, RoomMember, RoomSubmission
from app.workouts.models import WorkoutRecord


@pytest.fixture
def env():
    settings = Settings(
        APP_ENV="test",
        DATABASE_URL="postgresql+psycopg://localhost/unused",
        JWT_SECRET=secrets.token_urlsafe(32),
        JWT_ISSUER="rooms-tests",
        JWT_AUDIENCE="mobile",
    )
    app = create_app(settings)
    engine = create_engine(
        "sqlite+pysqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(
        engine,
        tables=[
            ChallengeRoom.__table__,
            RoomMember.__table__,
            WorkoutRecord.__table__,
            RoomSubmission.__table__,
        ],
    )
    players = [
        SimpleNamespace(user_id=uuid4(), username="Player_%d" % i) for i in range(3)
    ]
    current = [0]
    app.dependency_overrides[get_session] = lambda: Session(engine)
    app.dependency_overrides[get_current_user] = lambda: players[current[0]]
    with patch("app.main.create_database_engine", return_value=engine):
        with TestClient(app) as client:
            yield client, engine, players, current
    engine.dispose()


def setup_room(env):
    client, _, players, current = env
    created = client.post(
        "/api/v1/rooms", json={"title": "Friends November challenge", "max_players": 3}
    )
    assert created.status_code == 201, created.text
    room = created.json()
    current[0] = 1
    joined = client.post(
        "/api/v1/rooms/join", json={"invite_code": room["invite_code"].lower()}
    )
    assert joined.status_code == 200, joined.text
    return room


def add_workout(engine, user_id, exercise, value, start_after):
    with Session(engine) as session:
        record = WorkoutRecord(
            user_id=user_id,
            exercise=exercise,
            metric="hold_ms" if exercise == "plank" else "reps",
            reps=0 if exercise == "plank" else value,
            hold_ms=value if exercise == "plank" else 0,
            active_ms=max(10000, value),
            source="device_reported",
            created_at=start_after + timedelta(seconds=3),
        )
        session.add(record)
        session.commit()
        return str(record.workout_id)


def test_room_end_to_end_and_overall_ranking(env):
    client, engine, players, current = env
    room = setup_room(env)
    room_id = room["room_id"]
    assert room["status"] == "waiting"
    assert len(room["members"]) == 1
    assert client.post(f"/api/v1/rooms/{room_id}/start").status_code == 403
    assert len(client.get("/api/v1/rooms").json()) == 1
    current[0] = 2
    assert client.get(f"/api/v1/rooms/{room_id}").status_code == 404
    current[0] = 0
    started = client.post(f"/api/v1/rooms/{room_id}/start")
    assert started.status_code == 200, started.text
    assert started.json()["status"] == "active"
    now = datetime.now(timezone.utc)
    push1 = add_workout(engine, players[0].user_id, "push_up", 14, now)
    push2 = add_workout(engine, players[1].user_id, "push_up", 10, now)
    plank1 = add_workout(engine, players[0].user_id, "plank", 30000, now)
    plank2 = add_workout(engine, players[1].user_id, "plank", 40000, now)
    for player, workout_id in [(0, push1), (1, push2), (0, plank1), (1, plank2)]:
        current[0] = player
        result = client.post(
            f"/api/v1/rooms/{room_id}/submissions", json={"workout_id": workout_id}
        )
        assert result.status_code == 200, result.text
    board = result.json()
    assert board["score_source"] == "device_reported_unverified"
    scores = {m["display_name"]: m for m in board["members"]}
    assert scores["Player_0"]["total_points"] == 3
    assert scores["Player_1"]["total_points"] == 3
    assert scores["Player_0"]["overall_rank"] == 1
    assert scores["Player_1"]["overall_rank"] == 1
    assert {x["exercise"]: x["total"] for x in scores["Player_0"]["exercises"]}[
        "push_up"
    ] == 14
    assert {x["exercise"]: x["total"] for x in scores["Player_1"]["exercises"]}[
        "plank"
    ] == 40000
    # Idempotent repeat does not increase total.
    current[0] = 0
    assert (
        client.post(
            f"/api/v1/rooms/{room_id}/submissions", json={"workout_id": push1}
        ).json()["members"][0]["total_points"]
        == 3
    )
    assert client.post(f"/api/v1/rooms/{room_id}/finish").status_code == 200
    assert (
        client.post(
            f"/api/v1/rooms/{room_id}/submissions", json={"workout_id": push1}
        ).status_code
        == 200
    )
    current[0] = 1
    assert client.post(f"/api/v1/rooms/{room_id}/finish").status_code == 403


def test_join_constraints_and_access_scope(env):
    client, _, _, current = env
    room = setup_room(env)
    room_id = room["room_id"]
    # Idempotent join works.
    assert (
        len(
            client.post(
                "/api/v1/rooms/join", json={"invite_code": room["invite_code"]}
            ).json()["members"]
        )
        == 2
    )
    current[0] = 2
    assert (
        client.post(
            "/api/v1/rooms/join", json={"invite_code": room["invite_code"]}
        ).status_code
        == 200
    )
    assert client.get(f"/api/v1/rooms/{room_id}").status_code == 200
    current[0] = 0
    assert client.post(f"/api/v1/rooms/{room_id}/start").status_code == 200
    assert client.post(f"/api/v1/rooms/{room_id}/start").status_code == 409
    assert (
        client.post(
            "/api/v1/rooms/join", json={"invite_code": "ZZZZZZZZZZ"}
        ).status_code
        == 404
    )
    assert client.post("/api/v1/rooms", json={"title": "X"}).status_code == 422


def test_reject_other_users_and_premature_workouts(env):
    client, engine, players, current = env
    room = setup_room(env)
    room_id = room["room_id"]
    current[0] = 0
    assert client.post(f"/api/v1/rooms/{room_id}/start").status_code == 200
    now = datetime.now(timezone.utc)
    prior = add_workout(
        engine, players[0].user_id, "squat", 3, now - timedelta(hours=3)
    )
    assert (
        client.post(
            f"/api/v1/rooms/{room_id}/submissions", json={"workout_id": prior}
        ).status_code
        == 409
    )
    other = add_workout(engine, players[1].user_id, "squat", 10, now)
    assert (
        client.post(
            f"/api/v1/rooms/{room_id}/submissions", json={"workout_id": other}
        ).status_code
        == 404
    )
    current[0] = 2
    assert (
        client.post(
            f"/api/v1/rooms/{room_id}/submissions", json={"workout_id": prior}
        ).status_code
        == 404
    )


def test_unauthenticated_room_endpoints():
    settings = Settings(
        APP_ENV="test",
        DATABASE_URL="postgresql+psycopg://localhost/unused",
        JWT_SECRET=secrets.token_urlsafe(32),
        JWT_ISSUER="test",
        JWT_AUDIENCE="mobile",
    )
    from unittest.mock import Mock

    app = create_app(settings)
    app.dependency_overrides[get_session] = lambda: Mock()
    with patch("app.main.create_database_engine", return_value=Mock()):
        with TestClient(app) as client:
            assert client.get("/api/v1/rooms").status_code == 401
            assert (
                client.post("/api/v1/rooms", json={"title": "Friends"}).status_code
                == 401
            )


def test_works_when_auth_dependency_already_opened_db_transaction(env):
    """Regression: get_current_user normally loads a User before room endpoint."""
    from fastapi import Depends
    from sqlalchemy import select

    client, engine, players, current = env
    # dependency override with the *same* get_session as route, opening txn
    from sqlalchemy.orm import Session

    from app.auth.dependencies import get_current_user
    from app.db import get_session

    def authenticated_user(db: Session = Depends(get_session)):
        db.execute(select(ChallengeRoom).limit(1)).all()
        return players[current[0]]

    client.app.dependency_overrides[get_current_user] = authenticated_user
    created = client.post(
        "/api/v1/rooms", json={"title": "Shared connection regression"}
    )
    assert created.status_code == 201, created.text
    current[0] = 1
    joined = client.post(
        "/api/v1/rooms/join", json={"invite_code": created.json()["invite_code"]}
    )
    assert joined.status_code == 200, joined.text
    current[0] = 0
    started = client.post("/api/v1/rooms/" + created.json()["room_id"] + "/start")
    assert started.status_code == 200, started.text
