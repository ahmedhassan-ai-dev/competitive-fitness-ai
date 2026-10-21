# Task 001 — MVP contracts and exercise interface

Date: 2026-10-21. Branch: feat/mvp-contracts. Contract version: 1.0.0.

## Outcome and changed files

- `packages/contracts/__init__.py`, `v1/__init__.py`: contract namespaces.
- `packages/contracts/v1/models.py`: typed MVP entities, REST bodies/receipts/errors,
  WebSocket score snapshot and provider-independent pose input.
- `packages/contracts/v1/generate.py`: deterministic schema/OpenAPI exporter.
- `packages/contracts/v1/schemas.json`, `openapi.json`: portable generated artifacts.
- `packages/contracts/v1/examples.json`: synthetic examples for each object model.
- `packages/contracts/tests/test_contracts.py`: examples, malformed input, semantic
  invariants, schema freshness, references and authentication requirements.
- `packages/contracts/README.md`: versioning, REST/WS, ownership, lifecycle,
  idempotency, ordering and authoritative score rules.
- `packages/exercise_engine/src/exercise_engine/__init__.py`, `engine.py`: Protocol,
  outputs and deterministic squat/push-up reference with temporal holds/hysteresis.
- `packages/exercise_engine/tests/test_engine.py`: synthetic movement/interface tests.
- `packages/exercise_engine/README.md`: orientation, timestamp, confidence, missing
  joints, normalization, transitions and limitations.
- `services/backend/pyproject.toml`: test discovery/import paths, test-only
  jsonschema dependency, explicit Ruff configuration.
- `.github/workflows/backend-ci.yml`: lint shared packages/backend; the existing
  pytest step now discovers shared tests through the backend configuration.
- `docs/reports/REPORT-002-mvp-contracts.md`: this checkpoint report.

Existing application code and Flutter files are unchanged. No auth, database,
camera, inference, UI or live networking implementation was added. No commit/push.

## Validation commands and results

From repository root (PowerShell):

```powershell
.\services\backend\.venv\Scripts\python.exe -m packages.contracts.v1.generate
.\services\backend\.venv\Scripts\python.exe -m pytest -c services/backend/pyproject.toml -q -p no:cacheprovider
python -m ruff check --config services/backend/pyproject.toml services/backend/app services/backend/tests packages/contracts packages/exercise_engine
python -m ruff format --config services/backend/pyproject.toml --check packages/contracts packages/exercise_engine
git diff --check
```

- Python: 98 passed, including the existing backend health test.
- Ruff: all checks passed; 10 Python files formatted.
- Diff whitespace check: passed (Git emits local LF/CRLF conversion notices).
- One existing dependency warning: Starlette TestClient deprecates httpx usage.

From `apps/mobile`:

```powershell
flutter test --no-pub
flutter analyze --no-pub
```

Flutter: 1 widget test passed; analysis found no issues. SDK-cache access required
running outside the filesystem sandbox. An earlier sandboxed `flutter test;
flutter analyze` attempt stalled and was interrupted; the commands above completed.

The initial `python -m pip install -e ".[dev]"` from services/backend failed because
the sandbox blocked PyPI access for build isolation. The existing environment
already had backend/pytest dependencies. The test-only dependency was then installed
successfully with network access using this repository-root command:

```powershell
.\services\backend\.venv\Scripts\python.exe -m pip install "jsonschema>=4.23,<5"
```

An initial 93/94 test run exposed skipped optional date-time format checking;
tests now explicitly register a stdlib date-time checker. The final 98-test suite
includes four additional lifecycle, rejected-event and threshold tests. No tests
were skipped. Android device/build, real pose inference, networking and database
integration checks were not run; this task does not implement those components.

## Risks and next steps

- Review the proposed contract with Mobile, Backend and AI owners before merge.
- Portable JSON Schema covers structural rules; documented cross-field validation
  must also be ported to native/Dart. Server ownership/order/state checks remain
  implementation work. Future FastAPI handlers need the specified ApiError envelope.
- Implement atomic event deduplication/sequence checks and score publication in a
  later vertical slice. Client pose claims are not anti-cheat evidence.
- Reference thresholds/form_score are provisional range-of-motion rules, with no
  held-out accuracy or alignment validation. Evaluate recorded clips across users
  and port the interface plus synthetic traces to Android.
- There is no reconnect replay/cursor, challenge timeout/cancellation, token
  refresh or engine persistence in v1. Restarting an engine within a session requires
  history replay to preserve event sequences/IDs.
- Generated schemas depend on Pydantic's exporter; regenerate and review artifacts
  when upgrading the FastAPI/Pydantic toolchain.
