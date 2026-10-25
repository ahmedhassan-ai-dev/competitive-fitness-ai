"""Migration wiring. Online access requires an explicit reviewed opt-in."""

from alembic import context
from sqlalchemy import create_engine
from sqlalchemy.pool import NullPool

from app.auth.models import User
from app.config import DatabaseSettings

target_metadata = User.metadata


def run_migrations_offline() -> None:
    # Validate the configured target without rendering its credentials into output.
    DatabaseSettings()
    context.configure(
        dialect_name="postgresql",
        target_metadata=target_metadata,
        literal_binds=True,
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    if (
        context.get_x_argument(as_dictionary=True).get("allow_database_migration")
        != "true"
    ):
        raise RuntimeError(
            "Online migrations require review and -x allow_database_migration=true"
        )
    settings = DatabaseSettings()
    engine = create_engine(
        settings.database_url.get_secret_value(),
        poolclass=NullPool,
        echo=False,
        hide_parameters=True,
        connect_args={"connect_timeout": 5, "options": "-c timezone=UTC"},
    )
    try:
        with engine.connect() as connection:
            context.configure(
                connection=connection,
                target_metadata=target_metadata,
                compare_type=True,
            )
            with context.begin_transaction():
                context.run_migrations()
    finally:
        engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
