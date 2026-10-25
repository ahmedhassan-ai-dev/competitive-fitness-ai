"""v1 errors only. 500/429 JSON extensions await contract review."""

from fastapi import FastAPI, Request
from fastapi.exception_handlers import http_exception_handler
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException
from starlette.responses import JSONResponse, PlainTextResponse

from packages.contracts.v1.models import ApiError

ERRORS = {
    401: ("unauthorized", "Authentication required or invalid credentials."),
    403: ("forbidden", "Access forbidden."),
    404: ("not_found", "Resource not found."),
    409: ("conflict", "Request conflicts with the current resource state."),
    422: ("validation_error", "Request validation failed."),
}


def error_response(status: int, headers=None) -> JSONResponse:
    code, message = ERRORS[status]
    error = ApiError(code=code, message=message)
    return JSONResponse(
        error.model_dump(mode="json"), status_code=status, headers=headers
    )


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(RequestValidationError)
    async def validation_error(request: Request, exc: RequestValidationError):
        # Do not echo validation inputs, request bodies, or exception details.
        return error_response(422)

    @app.exception_handler(HTTPException)
    async def http_error(request: Request, exc: HTTPException):
        if exc.status_code in ERRORS:
            return error_response(exc.status_code, exc.headers)
        if exc.status_code == 429:
            return PlainTextResponse(
                "Too Many Requests", status_code=429, headers=exc.headers
            )
        if exc.status_code >= 500:
            return PlainTextResponse(
                "Internal Server Error", status_code=exc.status_code
            )
        return await http_exception_handler(request, exc)

    @app.exception_handler(Exception)
    async def unexpected_error(request: Request, exc: Exception):
        return PlainTextResponse("Internal Server Error", status_code=500)
