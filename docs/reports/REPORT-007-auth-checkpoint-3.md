# Task 003, Checkpoint 3 — Authentication implementation

Date: 2026-10-23. Branch: feat/backend-auth. Ready for review; no commit/push/merge.

## Outcome and contract compatibility

Configured FastAPI applications now support POST /api/v1/auth/register (201) and
POST /api/v1/auth/token (200), matching OpenAPI operation IDs register/login.
Both use the existing shared AuthRequest and TokenResponse models. Requests require
case-sensitive ASCII username (3–32 letters/digits/underscores) and a password of
12–128 characters, reject extra fields, and perform no trimming/normalization.
Responses contain exactly access_token, token_type=bearer, expires_in=900 and UUID
user_id. A test compares runtime schemas, operations and response statuses with
the approved OpenAPI. No shared contract/generated artifact was modified.

get_current_user provides authenticated lookup for future protected routes. v1 has
no /me route or public-user schema, so no new lookup endpoint was invented; a
test-only protected route exercises the dependency. Health-only create_app() and
the existing app import remain unchanged in behavior; authentication is mounted
only for configured instances. No new ORM model or migration was needed.

## Exact files changed in this checkpoint

| File | Purpose |
| --- | --- |
| services/backend/app/auth/security.py | Explicit Argon2id parameters, salted hashing/verification, dummy verification, rehash checks, minimal HS256 issuance and strict token validation |
| services/backend/app/auth/dependencies.py | Configured settings/password dependencies, generic bearer 401, validated UUID-to-User lookup |
| services/backend/app/auth/service.py | Transactional register/login, database-arbitrated username conflicts, password rehash on valid login, commit-before-response |
| services/backend/app/auth/routes.py | Exact v1 paths/models/statuses/operation IDs, ApiError response documentation and no-store token responses |
| services/backend/app/main.py | Mount auth only in configured apps; own and release per-app password service during lifespan |
| services/backend/pyproject.toml | Add argon2-cffi >=25.1,<26 and PyJWT >=2.10.1,<3 |
| services/backend/tests/test_auth_security.py | 37 password/JWT tests, including missing/malformed claims, bad algorithms/signatures/types/issuer/audience/expiry |
| services/backend/tests/test_auth_routes.py | 13 OpenAPI, response, cache-header and input-validation tests |
| services/backend/integration_tests/auth_cases.py | 23 real PostgreSQL HTTP/auth/concurrency/rollback tests; test-only protected route |
| services/backend/testing/postgres.py | Select auth_cases.py alongside the existing database suite in the owned-container runner |
| services/backend/README.md | Request flow, password/JWT policy, dependency usage, contract limitations and deployment follow-up |
| docs/architecture/postgresql-test-environment.md | Document auth fixtures and runner selection while retaining the same isolation boundary |
| docs/reports/REPORT-007-auth-checkpoint-3.md | This report |

Previous checkpoint and unrelated workspace edits were preserved. Existing test
files were not edited. No changes to User metadata, database infrastructure,
Alembic revision, error handlers, CI workflow or Flutter files in this checkpoint.

## Security and transaction decisions

argon2-cffi supplies the password primitive; PyJWT supplies JWT encoding/validation.
No custom cryptographic algorithm was implemented. Installed versions are
argon2-cffi 25.1.0 and PyJWT 2.15.1. Argon2id uses 64 MiB, 3 iterations, 4 lanes,
32-byte output and library-generated 16-byte random salts. Only encoded hashes
are persisted. Successful login upgrades outdated parameters transactionally.
Missing users undergo verification with a per-application random dummy hash.

Registration hashes before opening its transaction, inserts/flushed User, creates
the response, and commits before returning it. PostgreSQL's uq_users_username
constraint is authoritative; its specific 23505 violation produces generic 409.
There is no race-prone check-then-insert. Failed inserts or token construction roll
back. Login verification, optional rehash and token construction share a transaction.
The existing request dependency closes sessions; failures roll back and sessions
can be reused after the service transaction exits. Real tests verify these properties.

Access tokens use the environment-provided HS256 secret and exactly six claims:
sub, iss, aud, iat, exp, token_type=access. The header typ is at+jwt. Expiry is 900
seconds after issuance. Validation fixes the allowed algorithm, verifies signature,
exact issuer/single audience, required claims, expiration and future issuance,
strict integer times and lifetime, canonical non-nil UUID subject and both token
types. Unsupported critical headers are rejected. There is no clock-skew leeway.
The dependency accepts only a single bearer header and loads the actual User;
deleted/unknown users receive the same 401 as invalid credentials/tokens.

No passwords, signing secrets, hashes or access tokens are logged by this code.
No plaintext passwords/access tokens are stored in PostgreSQL. Responses containing
tokens disable caching. Invalid input uses sanitized existing 422 ApiError; auth
failures use existing 401 ApiError plus WWW-Authenticate: Bearer; username conflicts
use existing 409 ApiError. A logging test checks that successful auth does not emit
the generated password, signing secret or either access token.

## Contract ambiguities and limits

- v1 requires duplicate registration to return 409, revealing username availability.
  Generic text cannot remove that status-level disclosure. Complete registration
  non-enumeration would require a reviewed contract change. Login wrong-password
  and missing-user responses are identical; dummy hashing reduces timing differences
  but does not establish constant-time end-to-end HTTP behavior.
- No public-user lookup schema/path exists; the reusable dependency satisfies lookup
  without extending the API. Future routes must serialize approved DTOs, never User
  directly, because the ORM object contains password_hash.
- 500 internal_error and 429 rate_limited remain outside approved v1. Existing sanitized
  plain-text fallback remains, including the injected internal-failure test. No new
  error enum or disguised 401/409 for infrastructure failure was introduced.
- JWT claim/header details are an internal access-token profile; the public token
  stays opaque under TokenResponse. Tokens issued in the same second for one user
  may be identical; no uniqueness/revocation claim or persisted token is needed here.

No compatibility-breaking change or unresolved decision blocked this scope.

## Validation

Commands executed from repository root (PowerShell):

```powershell
.\services\backend\.venv\Scripts\python.exe -m pip install -e ./packages/contracts -e './services/backend[dev]'
.\services\backend\.venv\Scripts\python.exe -m ruff check --fix --config services/backend/pyproject.toml services/backend/app/auth services/backend/app/main.py services/backend/tests/test_auth_security.py services/backend/tests/test_auth_routes.py services/backend/integration_tests/auth_cases.py
.\services\backend\.venv\Scripts\python.exe -m ruff format --config services/backend/pyproject.toml services/backend/app/auth services/backend/app/main.py services/backend/tests/test_auth_security.py services/backend/tests/test_auth_routes.py services/backend/integration_tests/auth_cases.py
.\services\backend\.venv\Scripts\python.exe -m pytest -c services/backend/pyproject.toml -q -p no:cacheprovider --basetemp "$env:TEMP/task003-cp3-$([guid]::NewGuid().ToString('N'))"
.\services\backend\.venv\Scripts\python.exe -m ruff check --config services/backend/pyproject.toml services/backend/app services/backend/tests services/backend/alembic services/backend/testing services/backend/integration_tests packages/contracts packages/exercise_engine
.\services\backend\.venv\Scripts\python.exe -m ruff format --check --config services/backend/pyproject.toml services/backend/app services/backend/tests services/backend/alembic services/backend/testing services/backend/integration_tests
git diff --check
```

**229 passed in 6.56 seconds:** all 179 previous unit/reference tests plus 50 new
tests. Ruff lint passed; format check passed for 28 files; whitespace check passed.

From services/backend:

```powershell
.\.venv\Scripts\python.exe -m testing.postgres
```

**43 passed in 5.31 seconds:** all 20 existing PostgreSQL tests plus 23 auth tests.
The runner also passed upgrade/head, downgrade/base, and re-upgrade/head checks.
**Total: 272 passing pytest cases; zero failures or skips.** Both suites retain one
existing Starlette/httpx deprecation warning. Git emitted existing CRLF conversion
warnings without whitespace failures. No failed test run occurred in this checkpoint.

Auth integration coverage includes stored Argon2id verification, registration/login,
case sensitivity, duplicate/invalid credentials, malformed/bad/expired tokens,
protected lookup, duplicate authorization headers, unknown/deleted subjects, real
concurrent registration (one 201, one 409, exactly one row), token-issuance failure
rollback, session reuse after conflict, hash upgrades, and exact Unicode/whitespace
password preservation. Tests use production hashing parameters except the explicit
old-parameter fixture for rehash testing. No timing or performance benchmark is claimed.

Local environment: Python 3.13, SQLAlchemy 2.0.55, psycopg 3.3.6, Alembic 1.20.1,
Docker 29.9.2, PostgreSQL 17.6. CI Python 3.11, Flutter, production/TLS and load tests
were not run. All database tests used the existing disposable runner; no development
or production database was accessed.

## Docker cleanup evidence

The run created container
`c723a06914c9619e30b1f744cf4eb212c9fa92d055e3c859c3a7430dc6e47107`
named `fitness-pg-test-07a65f0beace4502b78f6499eb9f1303`, with localhost port 53900.
The runner verified zero persistent mounts, performed finally cleanup and verified
the full ID absent. The pinned PostgreSQL image digest remains the Checkpoint 2.5
baseline. An independent read-only check executed:

```powershell
$taskContainerId = 'c723a06914c9619e30b1f744cf4eb212c9fa92d055e3c859c3a7430dc6e47107'
$taskRemaining = @(docker ps -aq --no-trunc --filter "id=$taskContainerId")
if ($LASTEXITCODE -ne 0 -or $taskRemaining.Count -ne 0) { throw 'Cleanup verification failed' }
Write-Output "ABSENT $taskContainerId"
$taskLabels = @(docker ps -aq --no-trunc --filter 'label=competitive-fitness.integration-run')
if ($LASTEXITCODE -ne 0) { throw 'Docker inspection failed' }
Write-Output "Remaining integration-labelled containers: $($taskLabels.Count)"
```

Result: **ABSENT; remaining integration-labelled containers: 0**. No persistent
volumes were created or removed, and no unrelated Docker resources were removed.

## Remaining work and next step

Stop for review. Before public deployment, review TLS, secret management/rotation,
credential-safe observability, rate limiting/abuse controls and Argon2 concurrency
capacity. Each hash needs about 64 MiB plus overhead; worker sizing needs measurement.
A lost response after a successful commit can leave registration completed; v1
offers login or duplicate 409, not a registration idempotency key. Revocation storage,
refresh tokens, reset and verification flows remain outside scope. Individual tokens
expire after 900 seconds; deleting a user or rotating the signing secret invalidates
lookup. Dedicated integration CI and production migration rollout remain separate work.

Review the pending versioned 500/429 proposal before implementing rate-limit JSON
errors. After approval of this checkpoint, future protected features can reuse
get_current_user and the validated transaction infrastructure.

References: [argon2-cffi API](https://argon2-cffi.readthedocs.io/en/stable/api.html)
and [PyJWT validation API](https://pyjwt.readthedocs.io/en/stable/api.html).
