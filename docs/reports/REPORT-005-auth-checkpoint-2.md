# Task 003, Checkpoint 2 — PostgreSQL infrastructure and migration review

Date: 2026-10-23. Branch: feat/backend-auth. Prepared for review; no commit/push/merge.

## Outcome

Added synchronous SQLAlchemy 2.0/psycopg infrastructure, lazy configured-app engine
lifespan, request-scoped sessions, User metadata and the initial Alembic revision.
Health remains connection-free and returns the original response. No table creation
or migration runs at startup. No database connection, database migration, Docker
provisioning, authentication endpoint, hashing or JWT issuance occurred in this task.
The v1 contracts are unchanged.

## Exact changed files

| File | Purpose |
| --- | --- |
| services/backend/app/db.py | Declarative Base, lazy bounded PostgreSQL engine, session factory and cleanup-only request dependency |
| services/backend/app/auth/__init__.py | Persistence package namespace |
| services/backend/app/auth/models.py | User UUID key, case-sensitive username/unique constraint, format checks, Argon2id hash storage, aware created_at |
| services/backend/app/config.py | Extract DatabaseSettings so Alembic validates DATABASE_URL without requiring JWT configuration; existing Settings inherits the same validation |
| services/backend/app/main.py | Create lazy engine/session factory in configured lifespan, clear resources and dispose on shutdown/setup failure |
| services/backend/pyproject.toml | SQLAlchemy 2.0, psycopg binary driver and Alembic dependencies |
| services/backend/alembic.ini | Repository-relative script location and portable path parsing, no URL or credentials |
| services/backend/alembic/env.py | Environment-only target configuration, offline PostgreSQL rendering, guarded online execution and engine disposal |
| services/backend/alembic/script.py.mako | Future migration revision template |
| services/backend/alembic/versions/0001_create_users.py | Initial users-table upgrade definition and explicitly destructive downgrade definition |
| services/backend/tests/test_user_model.py | Metadata, UUID defaults, named constraints, PostgreSQL DDL and representation checks |
| services/backend/tests/test_db.py | Lazy engine, distinct sessions, cleanup on normal/error/cancel paths, fail-closed dependency, lifespan cleanup; connections prohibited |
| services/backend/tests/test_migration_definitions.py | Single revision head, recorded upgrade/model DDL equivalence, recorded downgrade target, database-only settings, offline wiring and online opt-in guard |
| services/backend/README.md | Resource ownership, pool limits, schema, migration lifecycle and review instructions |
| .github/workflows/backend-ci.yml | Include Alembic Python files in existing Ruff check; existing install/tests remain intact |
| docs/architecture/postgresql-test-environment.md | Proposed disposable container, isolated credentials/roles, guarded target selection, transaction strategy and ownership-based cleanup |
| docs/reports/REPORT-005-auth-checkpoint-2.md | This report |

Existing tests were not edited. Unrelated edits to REPORT-002 and REPORT-004 were
left untouched; the latter appeared during this work and changes its final newline.

## Database/migration review notes

Each configured process has a pool of 5 plus at most 5 overflow connections. Engines
do not connect until SQL is requested. Sessions are separate per request, autoflush
is disabled, and the dependency never commits. Close rolls back remaining work;
service transaction scopes will own commit/rollback. Health uses no Session.

The migration uses UUID (application-generated uuid4 on ORM inserts), VARCHAR(32)
COLLATE "C", TEXT and TIMESTAMPTZ DEFAULT now(). The unique constraint is named
uq_users_username. Username format is constrained to the v1 ASCII pattern. The
hash prefix check excludes other schemes but cannot establish valid Argon2id
encoding, strength or correctness. No hashing code is included.

Alembic loads its environment, follows revision/down_revision links and records
applied revisions in alembic_version during future execution. Upgrade creates the
users table; downgrade drops it and loses its data. Historical revisions carry
their own schema definitions, independent of later ORM changes. Online execution
requires explicit allow_database_migration=true opt-in and separate review of
target, roles and backup/rollback policy. The flag does not itself establish approval.

No Alembic migration command was executed. Unit tests invoke definition functions
with create_table/drop_table replaced by recording mocks, then compile PostgreSQL
DDL in memory. Environment tests replace the runner and prohibit engine creation.
This validates definitions and wiring, not live PostgreSQL enforcement.

## Validation

Commands executed from repository root (PowerShell):

```powershell
.\services\backend\.venv\Scripts\python.exe -m pip install -e ./packages/contracts -e './services/backend[dev]'
.\services\backend\.venv\Scripts\python.exe -m ruff check --fix --config services/backend/pyproject.toml services/backend/app services/backend/tests services/backend/alembic
.\services\backend\.venv\Scripts\python.exe -m ruff format --config services/backend/pyproject.toml services/backend/app services/backend/tests services/backend/alembic
.\services\backend\.venv\Scripts\python.exe -m pytest -c services/backend/pyproject.toml -q -p no:cacheprovider --basetemp "$env:TEMP/task003-cp2-final-$([guid]::NewGuid().ToString('N'))"
.\services\backend\.venv\Scripts\python.exe -m ruff check --config services/backend/pyproject.toml services/backend/app services/backend/tests services/backend/alembic packages/contracts packages/exercise_engine
.\services\backend\.venv\Scripts\python.exe -m ruff format --check --config services/backend/pyproject.toml services/backend/app services/backend/tests services/backend/alembic
git diff --check
```

**154 tests passed:** all 138 existing tests plus 16 new tests. Ruff lint/format and
whitespace checks passed. One existing Starlette/httpx deprecation remains. The
first successful test run also reported an Alembic path-parser deprecation; adding
path_separator=os and requiring Alembic >=1.16 removed it in the final run.

Local environment: Python 3.13, SQLAlchemy 2.0.55, psycopg 3.3.6, Alembic 1.20.1.
CI remains Python 3.11 and was not remotely executed. No tests skipped. PostgreSQL
integration, migration round-trip, real uniqueness races, TLS and Flutter checks
were not run. No Docker service is needed by the current suite.

## Limitations and next checkpoint

Review the migration and isolation proposal before any database execution. Next,
implement the disposable PostgreSQL test runner and test real upgrade/downgrade,
case-sensitive uniqueness, invalid inserts, UUID/time defaults and concurrent
transactions only in run-owned test databases. Production role provisioning,
verified TLS, deployment pool sizing and migration rollout remain operational work.
The existing 500/429 versioned error proposal is still pending; no new v1 codes
were introduced here.

Implementation references: SQLAlchemy's [session lifecycle documentation](https://docs.sqlalchemy.org/en/20/orm/session_basics.html)
and Alembic's [offline SQL documentation](https://alembic.sqlalchemy.org/en/latest/offline.html).
