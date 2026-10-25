from typing import Annotated

from fastapi import APIRouter, Depends, Response
from sqlalchemy.orm import Session

from app.auth import service
from app.auth.dependencies import get_passwords, get_settings
from app.auth.security import Passwords
from app.config import Settings
from app.db import get_session
from packages.contracts.v1.models import ApiError, AuthRequest, TokenResponse

router = APIRouter(
    prefix="/api/v1/auth",
    responses={status: {"model": ApiError} for status in (401, 403, 404, 409, 422)},
)
Database = Annotated[Session, Depends(get_session)]
Configuration = Annotated[Settings, Depends(get_settings)]
PasswordService = Annotated[Passwords, Depends(get_passwords)]


def prevent_token_caching(response: Response):
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"


@router.post(
    "/register", status_code=201, response_model=TokenResponse, operation_id="register"
)
def register(
    body: AuthRequest,
    response: Response,
    session: Database,
    settings: Configuration,
    passwords: PasswordService,
) -> TokenResponse:
    prevent_token_caching(response)
    return service.register(body, session, settings, passwords)


@router.post("/token", response_model=TokenResponse, operation_id="login")
def login(
    body: AuthRequest,
    response: Response,
    session: Database,
    settings: Configuration,
    passwords: PasswordService,
) -> TokenResponse:
    prevent_token_caching(response)
    return service.login(body, session, settings, passwords)
