"""Auth transactions commit before success is returned; failures roll back."""

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth.dependencies import unauthorized
from app.auth.models import User
from app.auth.security import Passwords, issue_access_token
from app.config import Settings
from packages.contracts.v1.models import AuthRequest, TokenResponse


def register(
    request: AuthRequest, session: Session, settings: Settings, passwords: Passwords
) -> TokenResponse:
    encoded = passwords.hash(request.password)
    try:
        with session.begin():
            user = User(username=request.username, password_hash=encoded)
            session.add(user)
            session.flush()
            response = issue_access_token(user.user_id, settings)
        return response
    except IntegrityError as error:
        # The database arbitrates concurrent inserts; only this constraint is 409.
        if (
            getattr(error.orig, "sqlstate", None) == "23505"
            and getattr(getattr(error.orig, "diag", None), "constraint_name", None)
            == "uq_users_username"
        ):
            raise HTTPException(status_code=409) from None
        raise


def login(
    request: AuthRequest, session: Session, settings: Settings, passwords: Passwords
) -> TokenResponse:
    with session.begin():
        user = session.scalar(select(User).where(User.username == request.username))
        valid = passwords.verify(request.password, user.password_hash if user else None)
        if not valid or user is None:
            raise unauthorized()
        if passwords.needs_rehash(user.password_hash):
            user.password_hash = passwords.hash(request.password)
        response = issue_access_token(user.user_id, settings)
    return response
