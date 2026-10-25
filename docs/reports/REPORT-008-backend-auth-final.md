# Task 003, Checkpoint 4 — Backend CI and final authentication validation

Date: 2026-10-25 (Africa/Cairo). Branch: feat/backend-auth. Ready for review.
No commit, push, merge, deployment or production/development migration performed.

## Outcome

The authentication milestone is validated locally and its GitHub Actions workflow
now includes the existing disposable PostgreSQL runner. All prior tests remain
passing. No public endpoint, v1 contract, ORM definition or migration was changed.
The actual hosted workflow has not run against these uncommitted changes; confirm
its first run after owner publication/review before claiming remote CI success.

## Architecture and request-flow review

FastAPI uses an application factory. The configured factory validates environment
settings, mounts authentication routes, and creates a per-app Argon2 password
service and lazy synchronous SQLAlchemy/psycopg engine during lifespan. The legacy
app.main:app remains health-only; deployments must explicitly select
app.main:create_configured_app --factory. Startup/health never creates tables or
runs migrations. Shutdown clears owned resources and disposes the engine.

Registration validates shared AuthRequest, hashes before opening its transaction,
inserts and flushes a User, constructs its token response, and commits before
returning success. PostgreSQL arbitrates duplicate/concurrent usernames. Only
the named uq_users_username unique violation becomes generic 409; unrelated
database failures retain internal-error handling. Failure before commit rolls back.

Login performs a case-sensitive lookup, verifies Argon2id, optionally updates an
outdated hash, creates the token, and commits within its transaction. Missing users
still undergo dummy-hash verification and receive the same 401 as wrong passwords.
The request dependency closes its Session; unfinished transactions roll back.

get_current_user validates a single bearer header and JWT before querying the User
by UUID. Invalid tokens and unknown/deleted subjects receive generic 401. This is
a reusable dependency, not a new public lookup endpoint. It leaves a read transaction
for request cleanup; future protected write handlers must reuse or explicitly finish
that transaction before starting another outer transaction on the same Session.
Future response models must not serialize the ORM User directly, which includes its hash.

## Exact API endpoints and contract review

| Method/path | Request | Success |
| --- | --- | --- |
| GET /api/v1/health | None | 200 with status=ok |
| POST /api/v1/auth/register | AuthRequest | 201 TokenResponse; operationId register |
| POST /api/v1/auth/token | AuthRequest | 200 TokenResponse; operationId login |

AuthRequest contains exactly required username and password. Username matches
`^[A-Za-z0-9_]{3,32}$`; password is 12–128 characters. Extra fields are rejected.
Fields are not lowercased, trimmed or normalized. TokenResponse contains exactly
access_token, token_type=bearer, expires_in=900 and UUID user_id. Token responses
disable caching. Runtime route/model/status compatibility is tested against the
approved OpenAPI. The approved v1 directory has no diff.

Invalid requests use generic 422 ApiError. Auth failures use generic 401 ApiError
and WWW-Authenticate: Bearer. Duplicate registration uses generic 409 ApiError.
The envelope has only code and message. v1 has no /me, refresh/logout, reset or
email-verification routes; none were introduced.

## Database schema and migration review

The model and revision 0001_create_users agree on table users:

| Column | Definition |
| --- | --- |
| user_id | Non-null PostgreSQL UUID primary key; application uuid4 default, no server UUID default |
| username | Non-null VARCHAR(32) COLLATE "C"; case-sensitive uq_users_username |
| password_hash | Non-null TEXT holding encoded Argon2id only |
| created_at | Non-null TIMESTAMPTZ DEFAULT now(); backend connections use UTC |

ck_users_username_format enforces the ASCII username pattern. The Argon2id-prefix
check only validates the storage prefix, not hash strength/validity. created_at
uses transaction-start time. Direct SQL must supply its UUID. No plaintext
password or access token column exists. Alembic tracks the revision separately.

The runner verifies container identity/label/name, localhost port, tmpfs and actual
database/user identity; it never accepts an existing DATABASE_URL. It creates
random credentials and distinct migration/runtime roles, runs upgrade, tests,
downgrade, and re-upgrade, then verifies table absence/recreation and revision state.
It closes resources and removes only its revalidated container in finally. No
second database lifecycle, service container or broad cleanup command was added.

## Security findings and decisions

No authentication-bypass or transaction-integrity defect was found in the reviewed
implementation. This is a focused code/test review, not a penetration test or
guarantee of production readiness.

- Passwords use argon2-cffi Argon2id with 64 MiB, 3 iterations, 4 lanes, 32-byte
  output and fresh random 16-byte salts. Missing-user dummy verification reduces
  a timing difference without claiming constant-time end-to-end requests.
- PyJWT uses only HS256 and the environment secret. Minimal claims are sub, iss,
  aud, iat, exp and token_type=access; header typ is at+jwt. Validation checks
  signature, fixed algorithm, exact issuer/single audience, expiry/issuance,
  required claims and integer times, 900-second lifetime, canonical non-nil UUID
  subject, token type and unsupported critical headers. No clock-skew leeway.
- Secrets are required, masked in settings representations and have no development
  fallback. Application code does not log passwords, secrets or access tokens.
  SQL echo is disabled and SQLAlchemy hides parameters; logging/APM configuration
  must preserve credential safety independently.
- A CI disclosure gap was found and fixed: the runner redacted database credentials,
  but short pytest failure tracebacks/captures could expose fixture-generated auth
  passwords, signing secrets or tokens unknown to the parent process. Both CI tests
  and the existing integration runner now suppress tracebacks, captures, failure
  messages and warning details while retaining progress, counts and failure status.
  New subprocess tests deliberately fail assertions, setup and collection with
  generated canary credentials and verify that output does not contain them.
- New tests also verify downgrade/re-upgrade failures propagate and still execute
  cleanup. There is no continue-on-error or success masking in the workflow.

## CI changes

The existing backend job now uses GitHub-hosted ubuntu-24.04 and Python 3.11.
The official image inventory includes Docker; a required local-Docker preflight
also fails clearly if the daemon/CLI/context is unavailable or remote. The job
has a 20-minute limit, contents: read permissions, disabled persisted checkout
credentials, and no repository/database/JWT secrets. Triggers remain pull requests
and pushes to main, with manual workflow_dispatch added.

Required steps are:

1. Install both local shared contracts and backend dev dependencies.
2. Verify installed-contract import/resources with Python isolated mode.
3. Run all unit, reference-engine and contract compatibility tests.
4. Run Ruff lint over backend, test tooling, migrations and shared packages.
5. Run Ruff formatting checks over backend application/tests/migrations/tooling.
6. Verify access to a local Docker daemon using the runner's existing check.
7. Run python -m testing.postgres, including integration tests, migration round-trip
   and ownership-checked cleanup/absence verification.

Any command, test, migration, schema verification or cleanup failure fails the job.
Pytest plugin autoload is disabled in CI and the integration child. The workflow
does not publish raw diagnostic artifacts, dump environments or print Docker logs.
No database URL or generated credential is placed in shell commands/workflow YAML.

## Exact files changed in Checkpoint 4

| File | Purpose |
| --- | --- |
| .github/workflows/backend-ci.yml | Ubuntu/Docker preflight, full test/lint/format/integration gates, restricted diagnostics and permissions |
| services/backend/testing/postgres.py | Central pytest output flags and safe failure guidance; existing ownership/database lifecycle retained |
| services/backend/tests/test_postgres_runner.py | Three credential-disclosure failure tests and two migration-round-trip failure/cleanup tests |
| services/backend/README.md | CI behavior, output policy, hosted-run status and updated integration readiness |
| docs/architecture/postgresql-test-environment.md | CI invocation and auth diagnostic protection with unchanged isolation rules |
| docs/reports/REPORT-008-backend-auth-final.md | This final report |

The workspace already contained prior milestone changes plus unrelated formatting
edits in REPORT-002/REPORT-004. They were reviewed and preserved. No authentication
implementation, v1 contract, migration definition or Flutter file was edited in
Checkpoint 4. No new dependencies were installed or added.

## Final validation results

| Check | Result |
| --- | --- |
| Complete Python suite | 234 passed, 1 existing warning, 8.64 seconds |
| Disposable PostgreSQL suite | 43 passed, 1 existing warning, 4.63 seconds |
| Total pytest cases | 277 passed; zero unexpected failures or skips |
| Contract compatibility | 63 cases included in the complete suite: 62 shared-contract cases plus runtime auth OpenAPI comparison |
| Migration upgrade/downgrade/re-upgrade | Passed, including revision and table-state checks |
| Ruff lint | Passed for backend, migrations, tooling/tests and shared contracts/engine |
| Ruff format | Passed for 28 backend Python files |
| Installed contract import/resource check | Passed |
| Workflow YAML/structural review | Passed: triggers, required gates, permissions, identical diagnostic flags, one existing runner invocation, no service database or secret references |
| Git whitespace check | Passed |
| Changed-file credential/artifact review | No accidental real credentials or temporary/private artifacts found |

The focused runner suite also passed 30 tests before the complete run. The five
new failure-path tests cover expected synthetic failures, not failing project tests.
One pre-existing Starlette/httpx deprecation warning remains in each full suite;
CI suppresses its message but reports the warning count. Existing Git CRLF notices
are not whitespace failures. An initial ad hoc YAML audit falsely matched the word
"secrets." in a comment; correcting it to inspect GitHub expression syntax passed.
No workflow defect or credential reference was present.

Commands executed from repository root (PowerShell):

```powershell
.\services\backend\.venv\Scripts\python.exe -m ruff check --fix --config services/backend/pyproject.toml services/backend/testing/postgres.py services/backend/tests/test_postgres_runner.py
.\services\backend\.venv\Scripts\python.exe -m ruff format --config services/backend/pyproject.toml services/backend/testing/postgres.py services/backend/tests/test_postgres_runner.py
.\services\backend\.venv\Scripts\python.exe -m pytest -c services/backend/pyproject.toml services/backend/tests/test_postgres_runner.py -q --tb=short -p no:cacheprovider --basetemp "$env:TEMP/task003-cp4-runner-$([guid]::NewGuid().ToString('N'))"
.\services\backend\.venv\Scripts\python.exe -m pytest -c services/backend/pyproject.toml -q --tb=no --show-capture=no --no-summary -rN --disable-warnings -p no:cacheprovider --basetemp "$env:TEMP/task003-cp4-final-$([guid]::NewGuid().ToString('N'))"
.\services\backend\.venv\Scripts\python.exe -m ruff check --config services/backend/pyproject.toml services/backend/app services/backend/tests services/backend/alembic services/backend/testing services/backend/integration_tests packages/contracts packages/exercise_engine
.\services\backend\.venv\Scripts\python.exe -m ruff format --check --config services/backend/pyproject.toml services/backend/app services/backend/tests services/backend/alembic services/backend/testing services/backend/integration_tests
.\services\backend\.venv\Scripts\python.exe -I -c "from packages.contracts.v1.models import AuthRequest; from importlib.resources import files; assert files('packages.contracts.v1').joinpath('schemas.json').is_file(); print('Installed contract import/resource check passed')"
git diff --check
```

The contract case count was collected without rerunning already-passing tests:

```powershell
.\services\backend\.venv\Scripts\python.exe -m pytest -c services/backend/pyproject.toml --collect-only -q packages/contracts/tests services/backend/tests/test_auth_routes.py::test_auth_paths_operations_and_schemas_match_approved_openapi -p no:cacheprovider
```

From services/backend, the live database command was:

```powershell
.\.venv\Scripts\python.exe -m testing.postgres
```

An ad hoc Python audit used the already-installed YAML parser to validate workflow
structure and compare its pytest arguments with the runner. A read-only scan of
modified/untracked text files checked private-key markers, credential-bearing
database URLs, GitHub token patterns, encoded JWTs, .env/private data and temporary
artifacts without printing candidate values. Manual review distinguished existing
synthetic fixtures from credentials. Pattern scanning is not an exhaustive secret
detector. The approved v1 and Flutter diffs are empty.

Local execution used Python 3.13 and Docker 29.9.2 with PostgreSQL 17.6. The test
image remains pinned to the reviewed digest from Checkpoint 2.5. Hosted Ubuntu/
Python 3.11 execution, Flutter, production TLS/deployment and load testing were
not performed. No GitHub workflow was triggered remotely.

## Docker cleanup evidence

Container: `1e4238ca1a0974d01c6ea34e58b49a0aa470611e2630b67d2f432b0ee467bc87`.
Name: `fitness-pg-test-7e7969e2762c495c9eb7dd61f9d3f870`.
Published port: 127.0.0.1:62045. Persistent mounts: zero.

The runner printed verified cleanup after successful migration round-trip. An
independent read-only verification executed:

```powershell
$taskContainerId = '1e4238ca1a0974d01c6ea34e58b49a0aa470611e2630b67d2f432b0ee467bc87'
$taskRemaining = @(docker ps -aq --no-trunc --filter "id=$taskContainerId")
if ($LASTEXITCODE -ne 0 -or $taskRemaining.Count -ne 0) { throw 'Cleanup verification failed' }
Write-Output "ABSENT $taskContainerId"
$taskLabels = @(docker ps -aq --no-trunc --filter 'label=competitive-fitness.integration-run')
if ($LASTEXITCODE -ne 0) { throw 'Docker inspection failed' }
Write-Output "Remaining integration-labelled containers: $($taskLabels.Count)"
```

Result: **exact container ABSENT; remaining integration-labelled containers: 0**.
No persistent volume or unrelated Docker resource was created/removed by cleanup.
The downloaded image cache remains intentionally. No global prune was used.

## Known limitations and remaining integration tasks

- Confirm the first hosted workflow run after owner publication, then require the
  backend check through repository branch protection as appropriate. No branch
  protection or repository settings were changed here.
- v1's required duplicate-registration 409 exposes username availability. Full
  registration non-enumeration needs a contract decision. 500/429 remain sanitized
  plain text pending the separate versioned error proposal; rate limiting was not added.
- Before public deployment, review HTTPS/database TLS, runtime/migration roles,
  secure secret injection/rotation, credential-safe proxy/APM logging, rate limiting
  and Argon2 concurrency/pool sizing. Each hash needs about 64 MiB plus overhead.
  Secret validation checks shape, not entropy. Synchronize clocks for zero-leeway JWTs.
- Dependency ranges and action major tags are not a fully locked supply chain.
  Maintain patch/dependency review and update the pinned PostgreSQL test image
  deliberately. This test image is not a production patch policy.
- Forced process termination or Docker failure can prevent finally cleanup. Local
  recovery must use the documented exact ownership checks. GitHub-hosted VMs are
  disposable; no unsafe alternate cleanup path was added.
- Refresh/logout, per-token revocation, reset and verification flows are outside v1.
  A lost response after successful registration commit can leave an existing account;
  login or the required duplicate response resolves the client flow.
- Future Flutter integration must use exact JSON names, protect token storage and
  handle expiration/401. Future backend protected routes must reuse get_current_user,
  respect transaction ownership and serialize approved response models. No Flutter,
  workout or challenge integration was implemented in this checkpoint.

Stop for review. The next action is owner review/publication and confirmation of
the hosted CI result, followed by explicitly scoped integration work.

References: [GitHub Ubuntu 24.04 runner inventory](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md),
[GitHub workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax),
and [pytest output controls](https://docs.pytest.org/en/stable/how-to/output.html).
