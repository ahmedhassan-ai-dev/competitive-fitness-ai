import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.main import create_app
from packages.contracts.v1.models import ApiError, AuthRequest


@pytest.fixture
def client():
    app = create_app()

    @app.get("/failure/{status}")
    def failure(status: int):
        raise HTTPException(
            status,
            detail="private exception detail",
            headers={"WWW-Authenticate": "Bearer"}
            if status == 401
            else {"Retry-After": "30"}
            if status == 429
            else None,
        )

    @app.post("/validate")
    def validate(body: AuthRequest):
        return {}

    @app.get("/unexpected")
    def unexpected():
        raise RuntimeError("private exception detail")

    with TestClient(app, raise_server_exceptions=False) as result:
        yield result


@pytest.mark.parametrize(
    "status,code",
    [
        (401, "unauthorized"),
        (403, "forbidden"),
        (404, "not_found"),
        (409, "conflict"),
        (422, "validation_error"),
    ],
)
def test_v1_http_errors(client, status, code):
    response = client.get(f"/failure/{status}")
    assert response.status_code == status
    assert ApiError.model_validate(response.json()).code == code
    assert "private" not in response.text
    assert set(response.json()) == {"code", "message"}
    if status == 401:
        assert response.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize(
    "body",
    [
        {"username": "x", "password": "sensitive-input"},
        {"username": "valid", "password": "sensitive-input", "extra": 1},
        None,
    ],
)
def test_validation_does_not_echo_inputs(client, body):
    response = client.post("/validate", json=body)
    assert response.status_code == 422
    assert response.json() == {
        "code": "validation_error",
        "message": "Request validation failed.",
    }
    assert "sensitive" not in response.text


def test_malformed_json_and_path(client):
    assert (
        client.post(
            "/validate", content="{broken", headers={"Content-Type": "application/json"}
        ).json()["code"]
        == "validation_error"
    )
    assert client.get("/failure/not-an-int").status_code == 422


def test_unknown_route(client):
    response = client.get("/does-not-exist")
    assert response.status_code == 404
    assert response.json()["code"] == "not_found"


@pytest.mark.parametrize(
    "path,status,text",
    [
        ("/unexpected", 500, "Internal Server Error"),
        ("/failure/500", 500, "Internal Server Error"),
        ("/failure/429", 429, "Too Many Requests"),
    ],
)
def test_unapproved_extensions_are_not_emitted(client, path, status, text):
    response = client.get(path)
    assert response.status_code == status
    assert response.text == text
    assert response.headers["content-type"].startswith("text/plain")
    if status == 429:
        assert response.headers["retry-after"] == "30"


def test_unmapped_http_status_keeps_framework_behavior(client):
    assert client.post("/api/v1/health").status_code == 405
