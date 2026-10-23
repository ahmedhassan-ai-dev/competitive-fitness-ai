# Backend configuration foundation

Checkpoint 1 implements packaging, configuration, app construction and error
infrastructure only. No database connections, migrations or authentication yet.

From `services/backend` in a virtual environment:

```powershell
python -m pip install -e ../../packages/contracts -e ".[dev]"
python -m pytest -q
python -m ruff check --config pyproject.toml app tests ../../packages/contracts ../../packages/exercise_engine
```

`uvicorn app.main:app --reload` preserves the configuration-free health scaffold.
It does not read settings and is not an authentication-ready production entry point.
`GET /api/v1/health` remains `200 {"status":"ok"}` and checks no external services.

Use `uvicorn app.main:create_configured_app --factory` for strict environment
validation before serving. `create_app(settings)` permits isolated test injection;
each factory call creates independent application state with debug disabled.
There is no import-time environment access or global settings cache. Future auth
routes must require configured settings rather than attach to an unconfigured app.

## Environment

Settings use pydantic-settings, accept constructor injection for tests, and never
automatically load `.env` files. Export variables explicitly or inject them through
the deployment environment. No real credentials should appear in examples or Git.

| Variable | Requirement |
| --- | --- |
| APP_ENV | Required: development, test or production |
| DATABASE_URL | Required: postgresql+psycopg URL with host and database |
| JWT_SECRET | Required: independently generated from >=32 random bytes |
| JWT_ISSUER | Required, nonblank, no surrounding whitespace |
| JWT_AUDIENCE | Required, nonblank, no surrounding whitespace |
| JWT_ALGORITHM | Optional; only HS256, default HS256 |
| ACCESS_TOKEN_TTL_SECONDS | Optional; only 900, default 900 |

Generate secrets outside source control. Length/distinct-character validation
catches trivial mistakes, not entropy or provenance. Secret and database URL
representations are masked; validation exception strings hide input values.
Do not log raw environment dictionaries or ValidationError.errors() input data.
URLs are validated structurally without installing a driver or opening connections.
TLS, runtime/migration roles, connectivity and pool policy belong to later checkpoints.

## Errors and contract boundary

HTTP 401/403/404/409/422 and request-validation failures produce the exact v1
`ApiError` shape, with fixed safe messages. HTTP exception details, validation
inputs and submitted passwords are not echoed. Exception headers, including
WWW-Authenticate, are preserved for supported statuses.

500 and 429 cannot currently be represented honestly by the v1 code enum.
Unexpected exceptions and explicit HTTP 500 use sanitized plain text `Internal
Server Error`; HTTP 429 uses `Too Many Requests` and preserves Retry-After headers.
Other unmapped HTTP statuses retain framework behavior (e.g. 405/Allow). This is
not a complete all-status JSON error contract. No rate limiter is implemented.
See `../../docs/architecture/auth-error-contract-proposal.md` for the pending
versioned extension. No v1 wire model or generated schema changes are authorized.
