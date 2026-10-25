"""Lazy synchronous PostgreSQL resources. No schema creation or implicit commits."""

from collections.abc import Iterator

from fastapi import Request
from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import DatabaseSettings


class Base(DeclarativeBase):
    pass


def create_database_engine(settings: DatabaseSettings) -> Engine:
    return create_engine(
        settings.database_url.get_secret_value(),
        echo=False,
        hide_parameters=True,
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=5,
        pool_timeout=30,
        connect_args={"connect_timeout": 5, "options": "-c timezone=UTC"},
    )


def create_session_factory(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_session(request: Request) -> Iterator[Session]:
    factory = getattr(request.app.state, "session_factory", None)
    if factory is None:
        raise RuntimeError(
            "Database sessions require a configured application lifespan"
        )
    with factory() as session:
        # Services own begin/commit. Close rolls back any remaining transaction.
        yield session
