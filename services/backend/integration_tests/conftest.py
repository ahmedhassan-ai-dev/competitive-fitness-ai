"""This suite must be launched through python -m testing.postgres."""

import pytest
from testing.postgres import RunnerError, Target

from app.config import DatabaseSettings
from app.db import create_database_engine, create_session_factory


@pytest.fixture(scope="session")
def engine():
    try:
        target = Target.from_test_environment()
    except RunnerError as error:
        pytest.fail(str(error), pytrace=False)
    engine = create_database_engine(
        DatabaseSettings(DATABASE_URL=target.url("runtime"))
    )
    try:
        yield engine
    finally:
        engine.dispose()


@pytest.fixture
def factory(engine):
    return create_session_factory(engine)
