"""Exercise catalog and authenticated, owner-scoped history tests."""
import secrets
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.auth.dependencies import get_current_user
from app.auth.models import User
from app.config import Settings
from app.db import Base, get_session
from app.main import create_app
from app.workouts.models import WorkoutRecord


@pytest.fixture
def app_and_user():
    settings = Settings(APP_ENV='test', DATABASE_URL='postgresql+psycopg://localhost/unused',
                        JWT_SECRET=secrets.token_urlsafe(32), JWT_ISSUER='test', JWT_AUDIENCE='mobile')
    application = create_app(settings)
    engine = create_engine('sqlite+pysqlite://', connect_args={'check_same_thread': False},
                           poolclass=StaticPool)
    Base.metadata.create_all(engine, tables=[WorkoutRecord.__table__])
    import app.main as main_module
    from unittest.mock import patch
    # Test the actual endpoints with an isolated sqlite engine and no external PostgreSQL.
    owner = uuid4()
    application.dependency_overrides[get_session] = lambda: Session(engine)
    application.dependency_overrides[get_current_user] = lambda: SimpleNamespace(user_id=owner)
    with patch('app.main.create_database_engine', return_value=engine):
        yield application, owner
    engine.dispose()


def test_catalog_has_four_exercises_with_correct_metric(app_and_user):
    app, _ = app_and_user
    with TestClient(app) as client:
        response = client.get('/api/v1/exercises')
    assert response.status_code == 200
    assert {x['id']: x['metric'] for x in response.json()} == {
        'squat': 'reps', 'push_up': 'reps',
        'jumping_jack': 'reps', 'plank': 'hold_ms',
    }
    assert all(not x['challenge_enabled'] for x in response.json())


def test_records_owner_scoped_and_metric_validated(app_and_user):
    app, owner = app_and_user
    with TestClient(app) as client:
        jacks = client.post('/api/v1/workouts', json={'exercise': 'jumping_jack', 'reps': 8,
                                                      'active_ms': 12000})
        assert jacks.status_code == 201, jacks.text
        assert jacks.json()['source'] == 'device_reported'
        plank = client.post('/api/v1/workouts', json={'exercise': 'plank', 'hold_ms': 9500,
                                                      'active_ms': 10000})
        assert plank.status_code == 201, plank.text
        assert client.post('/api/v1/workouts', json={'exercise': 'plank', 'reps': 4,
                                                     'active_ms': 10000}).status_code == 422
        assert client.post('/api/v1/workouts', json={'exercise': 'plank', 'hold_ms': 11000,
                                                     'active_ms': 10000}).status_code == 422
        assert client.post('/api/v1/workouts', json={'exercise': 'push_up', 'reps': -1,
                                                     'active_ms': 10000}).status_code == 422
        assert client.post('/api/v1/workouts', json={'exercise': 'burpee', 'active_ms': 1000}).status_code == 422
        history = client.get('/api/v1/workouts')
        assert history.status_code == 200, history.text
        assert len(history.json()) == 2
        assert {x['exercise'] for x in history.json()} == {'jumping_jack', 'plank'}
        assert client.get('/api/v1/workouts?limit=101').status_code == 422
        other = uuid4()
        app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(user_id=other)
        assert client.get('/api/v1/workouts').json() == []


def test_workouts_requires_auth_dependency_when_not_overridden():
    settings = Settings(APP_ENV='test', DATABASE_URL='postgresql+psycopg://localhost/unused',
                        JWT_SECRET=secrets.token_urlsafe(32), JWT_ISSUER='test', JWT_AUDIENCE='mobile')
    app = create_app(settings)
    from unittest.mock import Mock, patch
    app.dependency_overrides[get_session] = lambda: Mock()
    # Unauthorized requests stop at bearer auth, no DB query required.
    with patch('app.main.create_database_engine', return_value=Mock()):
      with TestClient(app) as client:
        assert client.get('/api/v1/workouts').status_code == 401
        assert client.post('/api/v1/workouts', json={'exercise': 'squat', 'reps': 2,
                                                     'active_ms': 900}).status_code == 401
