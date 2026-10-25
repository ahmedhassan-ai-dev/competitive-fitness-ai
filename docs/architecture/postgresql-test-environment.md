# Disposable PostgreSQL integration tests — Checkpoint 2.5

Implemented 2026-10-23; extended in Checkpoint 3 to run auth integration cases and
Checkpoint 4 (2026-10-25) to run unchanged database ownership/lifecycle checks in CI.
Scope is local, run-owned Docker resources only. The ORM, migration and v1 wire
contracts remain unchanged. The configured backend now exposes authentication.

## Schema review

The ORM and revision `0001_create_users` match: UUID primary key, not-null columns,
VARCHAR(32) COLLATE "C", named username unique/format constraints, Argon2id-prefix
check, and TIMESTAMPTZ DEFAULT now(). UUID generation is intentionally an ORM
uuid4 insert default, not a server default; direct SQL must supply a UUID.
PostgreSQL now() is transaction-start time, not a continuously advancing clock.
Backend connections use UTC; offset-aware timestamps preserve the same instant.
The password check validates only a prefix, not a real hash or its strength.
Session cleanup never commits; closing a session rolls back flushed rows.
No schema/constraint mismatch was found, and no migration edits were necessary.

## Lifecycle and isolation

1. `python -m testing.postgres` rejects remote Docker contexts/DOCKER_HOST overrides,
   checks Docker availability, and pulls PostgreSQL 17.6 Bookworm pinned by digest
   in `services/backend/testing/postgres.py`. The Docker image cache may remain.
2. Generate a random run ID, unique container/database/role names, and three
   independent 32-byte random passwords. Discard inherited DATABASE*, TEST_*, PG*,
   POSTGRES*, JWT*, token and pytest settings. No dotenv discovery or URL argument.
   Only this process changes environment; the invoking PowerShell session is untouched.
3. Create a labelled container, publish `127.0.0.1::5432`, and override the image's
   data volume with `/var/lib/postgresql/data` tmpfs (512 MiB). No named, anonymous,
   or bind-mounted persistent volumes. Secrets enter Docker via environment names,
   never CLI values. Inspect only safe fields, excluding Config.Env.
4. Check captured full container ID, exact name, random ownership label, localhost
   port and tmpfs storage before connecting. Readiness retries have a 60-second
   budget; individual Docker calls, connections and SQL also have bounded timeouts.
   A last in-flight probe can exceed the retry budget by its own timeout. Docker
   failures never fall back to SQLite or another database.
5. Confirm current_database()/current_user before DDL. Bootstrap separate LOGIN
   roles with NOSUPERUSER/NOCREATEDB/NOCREATEROLE: migration owns the database/schema;
   runtime receives only schema USAGE and SELECT/INSERT/UPDATE/DELETE on users.
6. Recheck container and database identity before each migration. Run Alembic with
   a freshly generated migration DATABASE_URL, APP_ENV=test and the existing
   allow_database_migration=true guard. Verify the users table and revision marker.
7. Launch pytest in a subprocess with generated runtime DATABASE_URL and matching
   TEST_DATABASE_URL, TEST_POSTGRES_RUN_ID, TEST_POSTGRES_CONTAINER_ID,
   TEST_POSTGRES_PORT, TEST_POSTGRES_PASSWORD, and APP_ENV=test. The fixture rebuilds
   the expected URL from these values, verifies ownership/identity, and refuses
   mismatches before ORM access. Auth fixtures construct configured apps with fresh
   in-memory JWT secrets and test issuer/audience, using only the verified runtime
   engine URL. No developer JWT setting is inherited or needed.
8. Test real constraints, committed UUID round-trips, case-sensitive usernames,
   concurrent duplicate inserts, UTC defaults and offset round-trips, role privileges,
   and flushed-row rollback on normal/error/cancel request cleanup. Each test uses
   unique records and closes its connections; committed rows live only until teardown.
   These tests use real transactions, not SQLite or mocked SQL. Auth cases additionally
   exercise registration/login through TestClient, token verification/protected-user
   lookup, concurrent registration, hash upgrades and failed-issuance rollback.
9. After pytest closes its engine, downgrade to base and verify users is absent and
   alembic_version empty. Re-upgrade and verify an empty users table and expected head.
   This is intentionally destructive only within the newly provisioned test database.
10. Finally, recheck ID/name/label and force-remove that specific container, then
    query its full ID to prove absence. Never prune or remove by a broad prefix.
    If create timed out before returning an ID, recover only the exact unique name
    plus matching label, then verify full identity before removal. Temporary pytest
    artifacts use a run-owned TemporaryDirectory. Failure/timeout returns nonzero.

No real credentials or user records are used. Subprocess diagnostics are withheld
when they might contain configuration; known database passwords/URLs are redacted.
Pytest assertion/traceback details, captures, failure messages and warning details
are suppressed so fixture-generated auth credentials also stay out of CI output.
Progress, counts and failure exit status remain visible. Docker administrators can
inspect container environment while it exists,
so use only these short-lived test credentials. tmpfs can use host swap; it is not
a guarantee of forensic erasure. No Docker logs/config dumps are printed.

## Windows PowerShell

Start Docker Desktop in Linux-container mode, select its local context and ensure
backend dependencies are installed in `services/backend/.venv`. From repository root:

```powershell
Push-Location services/backend
try {
    & ./.venv/Scripts/python.exe -m testing.postgres
    if ($LASTEXITCODE -ne 0) { throw 'Disposable PostgreSQL integration run failed' }
} finally {
    Pop-Location
}
```

No DATABASE_URL setup, Docker Compose file, administrator database, persistent
volume, hashing library or authentication endpoint is required. Use `python` in
place of the venv path on Linux or with an activated environment. The runner's
Docker CLI waits default to 30 seconds, create/migrations to 60 seconds, pytest
to 120 seconds and image pull to 300 seconds. Network access is needed for the pull.

The default local `python -m pytest -q` command remains Docker-free. The CI workflow
now runs that suite with restricted diagnostics, then invokes the existing Docker
runner on GitHub-hosted Ubuntu 24.04 after an explicit Docker preflight. It uses no
repository secrets, service database or alternate cleanup mechanism. Any test,
migration, schema check or cleanup failure fails the job. The integration modules
are named `postgres_cases.py` and `auth_cases.py` to avoid default collection, even
from repository root. The runner selects both. Direct invocation without the owned
test environment fails; no skip can disguise missing PostgreSQL validation.

## Cleanup failures and limitations

Normal completion, test failure, startup failure, timeouts and handled Ctrl+C all
enter finally. If Docker becomes unavailable or the process/host is forcibly killed,
cleanup cannot be guaranteed. Keep the printed container ID/name. After restoring
Docker, inspect only its ID, name and `competitive-fitness.integration-run` label;
compare all three with that run. Only after a match, remove that exact full ID and
verify `docker ps -aq --no-trunc --filter "id=<full ID>"` returns no rows. Never
remove an unverified container, use a prefix-wide deletion, or run Docker prune.

The pinned image is a reproducible test baseline, not a production image policy;
updating it needs review and another integration run. Production TLS/roles/backups,
production migration rollout and additional PostgreSQL versions remain follow-up
work. The workflow's first hosted run still needs confirmation after publication.
Future endpoint tests may use external transactions
and savepoints; concurrency tests must continue using separate committed connections.

References: [Docker tmpfs lifecycle and limitations](https://docs.docker.com/engine/storage/tmpfs/)
and [SQLAlchemy transaction management](https://docs.sqlalchemy.org/en/20/orm/session_transaction.html).
