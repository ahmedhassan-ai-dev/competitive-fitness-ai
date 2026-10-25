# Backend authentication foundation

Checkpoint 2 adds lazy synchronous PostgreSQL resources, User metadata and an
initial Alembic migration. Checkpoint 2.5 validates it only in disposable PostgreSQL.
Checkpoint 3 adds v1 registration/login, Argon2id, JWT access tokens and a reusable
authenticated-user dependency. No production migration has been executed.

From `services/backend` in a virtual environment:

```powershell
python -m pip install -e ../../packages/contracts -e ".[dev]"
python -m pytest -q
python -m ruff check --config pyproject.toml app tests alembic testing integration_tests ../../packages/contracts ../../packages/exercise_engine
```

`uvicorn app.main:app --reload` preserves the configuration-free health scaffold.
It does not read settings and is not an authentication-ready production entry point.
`GET /api/v1/health` remains `200 {"status":"ok"}` and checks no external services.

Use `uvicorn app.main:create_configured_app --factory` for strict environment
validation before serving. `create_app(settings)` permits isolated test injection;
each factory call creates independent application state with debug disabled.
There is no import-time environment access or global settings cache. Auth routes
attach only when Settings is provided. Configured lifespan creates an independent
password service/dummy hash and the lazy database resources, then releases them
on shutdown. Health remains independent of database connectivity.

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
URLs are validated structurally without opening connections. DatabaseSettings
validates DATABASE_URL alone for Alembic; Settings inherits it and retains the
existing application/JWT configuration requirements. Neither reads dotenv files.
TLS and runtime/migration-role provisioning require deployment-specific review.

## PostgreSQL resources and sessions

Configured apps create an engine and session factory during lifespan startup.
SQLAlchemy connects lazily on first SQL use, so startup and health make no database
connection. Shutdown disposes the engine and clears the factory, including when
session-factory setup fails. The unconfigured scaffold has no database resources.
No create_all, automatic migration, connectivity probe or seed data runs at startup.

The synchronous psycopg engine uses pre-ping, a bounded pool of 5 connections plus
5 overflow per worker, a 30-second pool wait, a 5-second connection timeout and UTC
database sessions. Size deployment worker counts against PostgreSQL's connection
budget. SQL echo is disabled and exception SQL parameters are hidden; never log
database settings, raw URLs, hashes or request passwords. Use verified TLS for a
remote database via reviewed DATABASE_URL parameters.

`get_session` yields one Session per request and closes it on success, failure or
cancellation. Close rolls back any remaining transaction. It never commits;
services must explicitly use transaction scopes. Sessions are not shared across
concurrent requests. Autoflush is disabled and committed objects do not expire.
The dependency fails closed outside a configured running application.

## User schema and migration review

`app/auth/models.py` declares `users` with these columns:

| Column | PostgreSQL definition |
| --- | --- |
| user_id | UUID primary key, not null; application uuid4 default on insert |
| username | VARCHAR(32) COLLATE "C", not null; uq_users_username unique constraint |
| password_hash | TEXT not null; encoded Argon2id storage only |
| created_at | TIMESTAMPTZ not null, database default now() |

`ck_users_username_format` enforces 3–32 ASCII letters, digits or underscores.
`C` collation makes the unique username comparison case-sensitive; no CITEXT or
lowercasing is used. `ck_users_password_hash_argon2id` requires the `$argon2id$`
prefix only. It cannot validate hash quality or verify a password. Authentication
uses the Argon2id password service described below. UUID generation is an ORM insert
default, not a database extension/default; direct SQL must supply a UUID.

Alembic reads `alembic.ini`, loads `alembic/env.py`, and follows revision links in
`alembic/versions`. The first revision is `0001_create_users`, with no parent.
Its upgrade defines the users table and constraints; its downgrade drops users
and therefore destroys user data. Applied revisions are tracked by Alembic in
the database's alembic_version table. The definition intentionally repeats schema
details rather than importing a mutable ORM model into a historical revision.

The environment obtains DATABASE_URL directly from validated environment settings,
never alembic.ini or a checked-in credential. Online operation uses a one-off
NullPool engine with UTC sessions and disposes it even after failure. It requires
the explicit `-x allow_database_migration=true` flag as an accidental-use guard;
the flag does not replace target/credential/migration review. The disposable test
runner supplies this flag only after checking its newly created container and
database identity. Development/production execution remains a separate reviewed
operational step with migration-role credentials.

Offline mode renders PostgreSQL SQL without a connection. Current unit tests go
further: they record migration operations and compile the recorded table in memory,
then compare it with ORM PostgreSQL DDL. They do not invoke Alembic's migration
runner or execute SQL. Review the revision and tests before approving database
execution. DDL compilation does not establish real PostgreSQL behavior.

## Disposable PostgreSQL tests (Windows PowerShell)

Start Docker Desktop with Linux containers and a local context. Use the backend
virtual environment with the dependencies above. From repository root:

```powershell
Push-Location services/backend
try {
    & ./.venv/Scripts/python.exe -m testing.postgres
    if ($LASTEXITCODE -ne 0) { throw 'Disposable PostgreSQL tests failed' }
} finally {
    Pop-Location
}
```

No exported database URL or credentials are needed. The runner discards inherited
database/libpq/JWT settings in its own process and generates its target exclusively
from a new container. It pulls PostgreSQL 17.6 Bookworm at a pinned image digest;
first execution requires registry access. No new Python dependencies are needed.

The runner creates a random localhost port and tmpfs data directory, checks
readiness, provisions separate migration/runtime roles, runs Alembic upgrade and
the database/authentication suites, then verifies downgrade and re-upgrade. Its finally block
removes only the captured container ID after checking ownership and verifies its
absence. Successful output includes the image digest, test count, migration result
and cleanup evidence. Never run Docker prune as test cleanup. If Docker stops or
the process is forcibly terminated, follow the ownership-checked recovery guidance
in [the test environment documentation](../../docs/architecture/postgresql-test-environment.md).

`python -m pytest -q` remains Docker-free. Integration cases deliberately use a
non-discovery filename and require the runner's proof of ownership when explicitly
selected; they never silently skip or accept an existing DATABASE_URL.

## GitHub Actions validation

`.github/workflows/backend-ci.yml` runs on pull requests, pushes to main, and
manual dispatch using a GitHub-hosted Ubuntu 24.04 VM with Python 3.11. It installs
the backend and shared contracts together, checks isolated installed-contract
imports/resources, runs all unit/reference/contract tests, runs Ruff lint and
backend formatting checks, verifies local Docker access, then invokes the same
`python -m testing.postgres` command used locally. No GitHub database service or
second database lifecycle is configured. The runner owns upgrade, integration
tests, downgrade/re-upgrade, and container cleanup/absence verification.

Each command is a required step; any nonzero exit fails the job. The job has a
20-minute limit, read-only contents permission, no persisted checkout credential,
and no repository/database/JWT secrets. The PostgreSQL image is pinned by digest;
Python dependency ranges and action major tags still require maintenance review.

CI and the integration runner suppress pytest tracebacks, captured output, failure
messages and warning details because those can contain generated passwords, JWTs
or signing secrets. Progress, result counts and exit status remain visible. Tests
exercise assertion, fixture-setup and collection failure paths to check this output
policy. Detailed failure diagnostics require careful local reproduction; do not
publish raw test responses, environments, Docker inspection or captured output.
Unexpected termination can still prevent finally cleanup; the GitHub-hosted VM is
disposable, and local recovery instructions remain in the test-environment document.

The workflow definition is validated locally. A hosted run of these changes must
be confirmed after the branch is pushed or a PR is opened by its owner.

## v1 authentication

Use the configured factory entry point above with environment-provided settings.
Both endpoints accept JSON AuthRequest directly from the shared contracts package:
required username matching `^[A-Za-z0-9_]{3,32}$`, required password of 12–128
characters, and no extra keys. Neither field is trimmed, lowercased or normalized.
Unicode passwords are encoded as UTF-8 for hashing. Invalid bodies return the
existing generic 422 ApiError; form-based OAuth requests are not the v1 contract.

| Route | OpenAPI operation | Success |
| --- | --- | --- |
| POST /api/v1/auth/register | register | 201 TokenResponse |
| POST /api/v1/auth/token | login | 200 TokenResponse |

TokenResponse has exactly access_token, token_type (`bearer`), expires_in (`900`),
and user_id (UUID). Success responses set Cache-Control: no-store and Pragma:
no-cache. Tests compare the runtime auth request/response schemas, status codes
and operation IDs with the checked-in OpenAPI. Shared v1 artifacts are unchanged.

Registration hashes before opening a database transaction, adds and flushes the
User, constructs its token response, then commits before returning success. The
named PostgreSQL uq_users_username constraint arbitrates duplicate/concurrent
requests; only that unique violation maps to generic 409 conflict. Other database
failures retain existing internal-error handling. Any failure during insert, token
construction or commit rolls back; request teardown closes its Session.

Login performs a case-sensitive lookup and verifies Argon2id. Missing users still
run verification against a per-application random dummy hash. Missing users and
wrong passwords receive identical generic 401 unauthorized responses and
WWW-Authenticate: Bearer. This reduces one timing difference; it is not a claim
of constant-time end-to-end HTTP behavior. Valid outdated hash parameters are
rehash-upgraded in the same transaction before returning a token.

argon2-cffi uses explicit Argon2id parameters: 64 MiB memory, 3 iterations, 4 lanes,
32-byte output and a fresh random 16-byte salt. Hashes alone are persisted. PyJWT
issues HS256 tokens using the validated environment secret, with exactly sub
(canonical non-nil UUID), iss, aud, iat, exp and token_type (`access`). The protected
header uses typ=`at+jwt`. exp is iat + 900 seconds. No username, password, hash,
refresh token, stored access token or other personal data is included in claims.

`app.auth.dependencies.get_current_user` is the reusable FastAPI dependency. It
requires a single Authorization bearer header, verifies signature using a fixed
HS256 allow-list, exact configured issuer/audience, required claims, expiration,
integer timestamps, issuance time and 900-second lifetime, UUID subject, and both
header/payload token type. It rejects unsupported critical headers. There is no
expiration leeway. It then loads the User from PostgreSQL; missing/deleted users
receive the same generic 401. Invalid tokens are rejected before a user query.
Do not serialize the returned ORM object directly: it contains password_hash;
future routes must build their approved response models explicitly.

v1 defines no `/me` path or public-user response. Lookup is therefore implemented
as a dependency; integration tests add a protected route only inside the test app.
No protected workout/challenge route or new external wire schema is added here.

## Authentication limits and deployment follow-up

v1 explicitly requires duplicate registration to return 409; this exposes username
availability despite the generic message. Complete registration non-enumeration
would require a reviewed contract change. Login does not distinguish missing users
from bad passwords. Existing 500/429 contract decisions below remain unresolved.

Before public deployment, review TLS termination, secret injection/rotation,
credential-safe access/APM logging, and abuse controls/rate limiting. The backend
does not log passwords, tokens or secrets; deployment middleware must preserve that
policy. Each concurrent Argon2 operation uses approximately 64 MiB plus overhead;
benchmark and size worker/concurrency limits for the deployment. No latency or
load-capacity guarantee is claimed. Synchronous endpoints run through FastAPI's
worker thread pool. A failed or lost HTTP response after commit can leave an
account created; the client can log in or observe the required duplicate 409.

No refresh/logout/revocation store, password reset or email verification is included.
Tokens expire after 900 seconds; removing a User invalidates lookup immediately,
and rotating the single signing secret invalidates existing tokens. PostgreSQL
production role/TLS setup and production migrations remain separate work. The
existing CI job now includes disposable PostgreSQL integration and migration checks.

Implementation references: [argon2-cffi API](https://argon2-cffi.readthedocs.io/en/stable/api.html)
and [PyJWT validation API](https://pyjwt.readthedocs.io/en/stable/api.html).

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
