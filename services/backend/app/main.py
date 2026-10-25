from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.auth.routes import router as auth_router
from app.auth.security import Passwords
from app.config import Settings
from app.db import create_database_engine, create_session_factory
from app.errors import install_error_handlers


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build an isolated app. Without settings this is the health-only scaffold."""

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        engine = None
        try:
            if settings is not None:
                application.state.passwords = Passwords()
                engine = create_database_engine(settings)
                application.state.session_factory = create_session_factory(engine)
            yield
        finally:
            application.state.passwords = None
            application.state.session_factory = None
            if engine is not None:
                engine.dispose()

    application = FastAPI(
        title="Competitive Fitness API", version="0.1.0", debug=False, lifespan=lifespan
    )
    application.state.settings = settings
    application.state.session_factory = None
    application.state.passwords = None
    install_error_handlers(application)
    if settings is not None:
        application.include_router(auth_router)

    @application.get("/api/v1/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    return application


def create_configured_app() -> FastAPI:
    """Strict server entry point; missing/invalid environment fails construction."""
    return create_app(Settings())


# Preserve the existing import and health-only CI behavior without dummy secrets.
app = create_app()
