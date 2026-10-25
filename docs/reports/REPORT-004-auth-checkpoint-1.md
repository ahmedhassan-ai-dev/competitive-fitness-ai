# Task 003, Checkpoint 1 — configuration and contract readiness

Date: 2026-10-22. Branch: feat/backend-auth. Ready for review; no commit/push/merge.

## Outcome

Shared contracts are independently installable as competitive-fitness-contracts
1.0.0 with unchanged Python imports and v1 wire artifacts. Backend settings are
environment-based, validated and secret-masked. A strict configured factory exists
alongside the preserved configuration-free health scaffold. Supported v1 HTTP
errors and request-validation failures use the shared ApiError model and sanitized
messages. No database, migration, auth, hashing, token issuance or rate limiter
was implemented or executed.

## Every changed file

| File | Purpose |
| --- | --- |
| packages/contracts/pyproject.toml | New installable distribution, Pydantic dependency, explicit package discovery and bundled JSON resources |
| packages/contracts/README.md | Independent installation and combined backend installation instructions |
| services/backend/pyproject.toml | Declare shared distribution and pydantic-settings dependencies |
| services/backend/app/config.py | Required environment settings, PostgreSQL URL checks, masked secrets, fixed HS256/900-second policy, no automatic dotenv loading |
| services/backend/app/main.py | Isolated create_app(settings), strict create_configured_app(), unchanged app import and health response |
| services/backend/app/errors.py | Shared ApiError for supported statuses, input redaction, preserved relevant headers, sanitized noncontract fallbacks |
| services/backend/tests/test_config.py | Required/invalid environment, redaction, defaults and dotenv isolation tests |
| services/backend/tests/test_app.py | App isolation, explicit injection, configured factory and scaffold behavior tests |
| services/backend/tests/test_errors.py | HTTP/validation envelopes, malformed input, redaction, headers, 500/429 boundary and framework fallbacks |
| services/backend/.env.example | Nonfunctional empty placeholders; no real secret or fallback |
| services/backend/README.md | Entry points, settings, installation, verification and interim contract limitations |
| .github/workflows/backend-ci.yml | Install both local packages and smoke-test installed imports/resources with Python isolated mode; retain existing test/lint steps |
| README.md | Update backend installation command and point to strict configuration instructions |
| docs/architecture/auth-error-contract-proposal.md | Proposed breaking 2.0.0 parallel contract for internal_error/rate_limited; review gates and fallback policy |
| docs/reports/REPORT-004-auth-checkpoint-1.md | This checkpoint record |

Pre-existing unrelated changes to REPORT-002-mvp-contracts.md and an unrelated
untracked root file were left untouched. No files under packages/contracts/v1 or
mobile were modified. Existing tests were preserved unchanged.

## Tests and verification

Commands from repository root, using the existing project virtual environment:

```powershell
.\services\backend\.venv\Scripts\python.exe -m pip install -e ./packages/contracts -e './services/backend[dev]'
.\services\backend\.venv\Scripts\python.exe -m pytest -c services/backend/pyproject.toml -q -p no:cacheprovider --basetemp "$env:TEMP/task003-cp1-$([guid]::NewGuid().ToString('N'))"
.\services\backend\.venv\Scripts\python.exe -m ruff check --config services/backend/pyproject.toml services/backend/app services/backend/tests packages/contracts packages/exercise_engine
.\services\backend\.venv\Scripts\python.exe -m ruff format --check --config services/backend/pyproject.toml services/backend/app services/backend/tests
.\services\backend\.venv\Scripts\python.exe -I -c "from packages.contracts.v1.models import AuthRequest; from importlib.resources import files; assert files('packages.contracts.v1').joinpath('schemas.json').is_file()"
git diff --check
git diff -- packages/contracts/v1
```

Results: **138 tests passed**, including all 98 existing backend/contracts/engine
tests and 40 focused new cases; Ruff lint/format and whitespace checks passed.
The v1 diff is empty. Existing Starlette/httpx TestClient deprecation warning remains.

An additional temporary-directory wheel smoke check ran these commands through a
Python subprocess harness (paths generated using tempfile.TemporaryDirectory):

```text
python -m pip wheel --no-deps --wheel-dir <temporary>/wheels <repo>/packages/contracts
python -m pip install --no-deps --target <temporary>/installed <built-wheel>
python -I -c <verification-script> <temporary>/installed
```

The script ran outside the repository, imported from the regular wheel installation
(asserting the module path), validated an example, and compared bundled schemas/
OpenAPI against exporter output. All passed. Temporary artifacts were cleaned up;
no wheels or credentials are committed. Installed dependency versions included
pydantic-settings 2.16.1 and Pydantic 2.14.1; Python was 3.13. CI remains Python 3.11
and was not remotely executed.

The first run exposed string-to-integer environment handling for the fixed lifetime
and overly broad redaction assertions; both were corrected. A restricted existing
pytest temporary root caused a permissions error; rerunning with a fresh UUID-named
temporary directory and appropriate access passed. No tests skipped. Database and
Flutter tests were not run: this checkpoint has no database or mobile changes.

## Unresolved decisions and next checkpoint

The existing v1 enum cannot express 500 internal_error or 429 rate_limited. The
proposal recommends a separate 2.0.0 contract/API path because strict consumers
may reject expanded enums. Until owners approve a rollout, unsupported 500/429
remain sanitized plain text rather than mislabeled v1 ApiError values. Other
unspecified HTTP statuses retain framework behavior. Full all-status JSON error
readiness remains unresolved; 503 coverage also needs a future decision.

The legacy app.main:app entry point is deliberately health-only and unconfigured;
strict environment validation requires app.main:create_configured_app --factory.
Future auth must require configured settings. Database TLS/roles/connectivity and
pool settings remain later work. Secret length checks do not establish entropy.

Next checkpoint after review: synchronous SQLAlchemy session infrastructure, users
schema and Alembic migration definition for review, followed by disposable PostgreSQL
test infrastructure. No development/production migrations should run automatically.
