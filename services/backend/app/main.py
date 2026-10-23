from fastapi import FastAPI

from app.config import Settings
from app.errors import install_error_handlers


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build an isolated app. Without settings this is the health-only scaffold."""
    application = FastAPI(title="Competitive Fitness API", version="0.1.0", debug=False)
    application.state.settings = settings
    install_error_handlers(application)

    @application.get("/api/v1/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    return application


def create_configured_app() -> FastAPI:
    """Strict server entry point; missing/invalid environment fails construction."""
    return create_app(Settings())


# Preserve the existing import and health-only CI behavior without dummy secrets.
app = create_app()
