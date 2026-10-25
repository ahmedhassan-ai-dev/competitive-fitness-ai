from typing import Annotated

from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.auth.models import User
from app.auth.security import InvalidAccessToken, Passwords, validate_access_token
from app.config import Settings
from app.db import get_session

bearer = HTTPBearer(auto_error=False)


def unauthorized() -> HTTPException:
    return HTTPException(status_code=401, headers={"WWW-Authenticate": "Bearer"})


def get_settings(request: Request) -> Settings:
    settings = request.app.state.settings
    if not isinstance(settings, Settings):
        raise RuntimeError("Authentication requires configured settings.")
    return settings


def get_passwords(request: Request) -> Passwords:
    passwords = request.app.state.passwords
    if passwords is None:
        raise RuntimeError("Authentication requires the application lifespan.")
    return passwords


def get_current_user(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    settings: Annotated[Settings, Depends(get_settings)],
    session: Annotated[Session, Depends(get_session)],
) -> User:
    if credentials is None or len(request.headers.getlist("authorization")) != 1:
        raise unauthorized()
    try:
        identity = validate_access_token(credentials.credentials, settings)
    except InvalidAccessToken:
        raise unauthorized() from None
    user = session.get(User, identity)
    if user is None:
        raise unauthorized()
    return user
