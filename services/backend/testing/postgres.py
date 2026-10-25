"""Run only against a fresh, owned Docker PostgreSQL; never accept a database URL."""

import json
import os
import re
import secrets
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from uuid import uuid4

import psycopg
from psycopg import sql
from sqlalchemy import URL

BACKEND = Path(__file__).resolve().parents[1]
IMAGE = "postgres:17.6-bookworm@sha256:f3bd19c606e442c3d7bdfa8002e03fe260a1023351e0ea4598032022b68dd6e3"
LABEL = "competitive-fitness.integration-run"
# Test failures can contain fixture-generated JWTs/passwords unknown to this parent.
# Keep progress and counts; never forward assertion details, captures or warnings.
PYTEST_OUTPUT_ARGS = [
    "-q",
    "--tb=no",
    "--show-capture=no",
    "--no-summary",
    "-rN",
    "--disable-warnings",
]


class RunnerError(RuntimeError):
    """Safe diagnostic: never include subprocess output or connection details."""


def clean_environment():
    return {
        key: value
        for key, value in os.environ.items()
        if not key.upper().startswith(
            ("PG", "POSTGRES", "DATABASE", "TEST_", "JWT", "ACCESS_TOKEN", "PYTEST")
        )
        and key.upper() != "APP_ENV"
    }


def command(args, *, env=None, timeout=30, check=True):
    try:
        result = subprocess.run(
            args, env=env, cwd=BACKEND, text=True, capture_output=True, timeout=timeout
        )
    except FileNotFoundError:
        raise RunnerError(
            "Required executable unavailable; install Docker and backend dev dependencies."
        ) from None
    except subprocess.TimeoutExpired:
        raise RunnerError("Subprocess exceeded its bounded timeout.") from None
    if not check:
        return result
    if result.returncode:
        raise RunnerError(
            "Subprocess failed; check Docker Desktop and backend dependencies. Raw output withheld to protect secrets."
        )
    return result.stdout.strip()


def docker(*args, **kwargs):
    return command(["docker", *args], **kwargs)


def require_local_docker():
    # Context inspection must describe the endpoint that Docker will actually use.
    if os.environ.get("DOCKER_HOST"):
        raise RunnerError(
            "Unset DOCKER_HOST; only a local Docker context is supported."
        )
    endpoint = docker("context", "inspect", "--format", "{{.Endpoints.docker.Host}}")
    if not endpoint.startswith(("npipe://", "unix://")):
        raise RunnerError(
            "Refusing a remote Docker context; select local Docker Desktop."
        )
    version = docker("version", "--format", "{{.Server.Version}}")
    print(f"Local Docker server: {version}", flush=True)


@dataclass
class Target:
    run_id: str = field(default_factory=lambda: uuid4().hex)
    container_id: str = ""
    port: int = 0
    admin_password: str = field(
        default_factory=lambda: secrets.token_urlsafe(32), repr=False
    )
    migration_password: str = field(
        default_factory=lambda: secrets.token_urlsafe(32), repr=False
    )
    runtime_password: str = field(
        default_factory=lambda: secrets.token_urlsafe(32), repr=False
    )

    @property
    def name(self):
        return f"fitness-pg-test-{self.run_id}"

    @property
    def database(self):
        return f"fitness_test_{self.run_id}"

    def role(self, kind):
        return f"{kind}_{self.run_id}"

    def url(self, kind):
        return URL.create(
            "postgresql+psycopg",
            username=self.role(kind),
            password=getattr(self, f"{kind}_password"),
            host="127.0.0.1",
            port=self.port,
            database=self.database,
        ).render_as_string(hide_password=False)

    def inspect(self, identifier):
        # Deliberately exclude Config.Env (contains bootstrap credentials).
        template = '{"id":{{json .Id}},"name":{{json .Name}},"labels":{{json .Config.Labels}},"ports":{{json .NetworkSettings.Ports}},"mounts":{{json .Mounts}},"tmpfs":{{json .HostConfig.Tmpfs}}}'
        return json.loads(docker("inspect", "--format", template, identifier))

    def verify_container(self, *, check_port=True):
        if not re.fullmatch(r"[0-9a-f]{32}", self.run_id) or not re.fullmatch(
            r"[0-9a-f]{64}", self.container_id
        ):
            raise RunnerError("Missing valid disposable container identity.")
        info = self.inspect(self.container_id)
        if (
            info["id"] != self.container_id
            or info["name"] != f"/{self.name}"
            or info["labels"].get(LABEL) != self.run_id
        ):
            raise RunnerError(
                "Container ownership mismatch; refusing access or deletion."
            )
        if check_port:
            mounts = info["mounts"]
            if any(m["Type"] != "tmpfs" for m in mounts) or not (
                "/var/lib/postgresql/data" in (info.get("tmpfs") or {})
                or any(m["Destination"] == "/var/lib/postgresql/data" for m in mounts)
            ):
                raise RunnerError(
                    "Database storage must be tmpfs with no persistent mounts."
                )
            ports = info["ports"].get("5432/tcp") or []
            if len(ports) != 1 or ports[0]["HostIp"] != "127.0.0.1":
                raise RunnerError("Database must be published only on localhost.")
            port = int(ports[0]["HostPort"])
            if not 1 <= port <= 65535 or (self.port and self.port != port):
                raise RunnerError("Published port mismatch.")
            self.port = port

    def connect(self, kind):
        # The runner and pytest child discard all libpq environment defaults.
        return psycopg.connect(
            host="127.0.0.1",
            hostaddr="127.0.0.1",
            port=self.port,
            dbname=self.database,
            user=self.role(kind),
            password=getattr(self, f"{kind}_password"),
            connect_timeout=2,
            options="-c timezone=UTC -c statement_timeout=10000",
            sslmode="disable",
            passfile="",
        )

    def verify_database(self, kind):
        self.verify_container()
        with self.connect(kind) as connection:
            row = connection.execute(
                "SELECT current_database(), current_user"
            ).fetchone()
            if row != (self.database, self.role(kind)):
                raise RunnerError("Database identity mismatch; refusing SQL.")

    def create(self):
        env = clean_environment()
        env.update(
            POSTGRES_USER=self.role("admin"),
            POSTGRES_PASSWORD=self.admin_password,
            POSTGRES_DB=self.database,
            POSTGRES_INITDB_ARGS="--auth-host=scram-sha-256",
        )
        self.container_id = docker(
            "create",
            "--name",
            self.name,
            "--label",
            f"{LABEL}={self.run_id}",
            "--publish",
            "127.0.0.1::5432",
            "--tmpfs",
            "/var/lib/postgresql/data:rw,size=512m",
            "--env",
            "POSTGRES_USER",
            "--env",
            "POSTGRES_PASSWORD",
            "--env",
            "POSTGRES_DB",
            "--env",
            "POSTGRES_INITDB_ARGS",
            IMAGE,
            env=env,
            timeout=60,
        )
        print(f"Created container: {self.container_id} ({self.name})", flush=True)
        docker("start", self.container_id)
        self.verify_container()
        deadline = time.monotonic() + 60
        while True:
            try:
                self.verify_database("admin")
                break
            except psycopg.OperationalError:
                if time.monotonic() >= deadline:
                    raise RunnerError(
                        "PostgreSQL did not become ready within 60 seconds."
                    ) from None
                time.sleep(0.5)
        print(f"Ready on 127.0.0.1:{self.port}; persistent mounts: 0", flush=True)

    def bootstrap(self):
        self.verify_database("admin")
        with self.connect("admin") as connection:
            for kind in ("migration", "runtime"):
                connection.execute(
                    sql.SQL(
                        "CREATE ROLE {} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD {}"
                    ).format(
                        sql.Identifier(self.role(kind)),
                        sql.Literal(getattr(self, f"{kind}_password")),
                    )
                )
            connection.execute(
                sql.SQL("ALTER DATABASE {} OWNER TO {}").format(
                    sql.Identifier(self.database),
                    sql.Identifier(self.role("migration")),
                )
            )
            connection.execute(
                sql.SQL("ALTER SCHEMA public OWNER TO {}").format(
                    sql.Identifier(self.role("migration"))
                )
            )
            connection.execute("REVOKE CREATE ON SCHEMA public FROM PUBLIC")
            print(
                f"PostgreSQL: {connection.execute('SHOW server_version').fetchone()[0]}",
                flush=True,
            )

    def migrate(self, direction, revision):
        self.verify_database("migration")
        env = clean_environment()
        env.update(APP_ENV="test", DATABASE_URL=self.url("migration"))
        command(
            [
                sys.executable,
                "-m",
                "alembic",
                "-c",
                str(BACKEND / "alembic.ini"),
                "-x",
                "allow_database_migration=true",
                direction,
                revision,
            ],
            env=env,
            timeout=60,
        )

    def verify_schema(self, present):
        self.verify_database("migration")
        with self.connect("migration") as connection:
            exists = connection.execute(
                "SELECT to_regclass('public.users') IS NOT NULL"
            ).fetchone()[0]
            revisions = connection.execute(
                "SELECT version_num FROM alembic_version"
            ).fetchall()
            if exists != present or revisions != (
                [("0001_create_users",)] if present else []
            ):
                raise RunnerError("Migration schema/revision verification failed.")
            if (
                present
                and connection.execute("SELECT count(*) FROM users").fetchone()[0] != 0
            ):
                raise RunnerError("Freshly migrated users table must be empty.")

    def grant_runtime(self):
        self.verify_database("migration")
        with self.connect("migration") as connection:
            connection.execute(
                sql.SQL("GRANT USAGE ON SCHEMA public TO {}").format(
                    sql.Identifier(self.role("runtime"))
                )
            )
            connection.execute(
                sql.SQL("GRANT SELECT, INSERT, UPDATE, DELETE ON users TO {}").format(
                    sql.Identifier(self.role("runtime"))
                )
            )

    def test_environment(self):
        env = clean_environment()
        env.update(
            APP_ENV="test",
            TEST_POSTGRES_RUN_ID=self.run_id,
            TEST_POSTGRES_CONTAINER_ID=self.container_id,
            TEST_POSTGRES_PORT=str(self.port),
            TEST_POSTGRES_PASSWORD=self.runtime_password,
            TEST_DATABASE_URL=self.url("runtime"),
            DATABASE_URL=self.url("runtime"),
            PYTEST_DISABLE_PLUGIN_AUTOLOAD="1",
        )
        return env

    @classmethod
    def from_test_environment(cls):
        try:
            target = cls(
                run_id=os.environ["TEST_POSTGRES_RUN_ID"],
                container_id=os.environ["TEST_POSTGRES_CONTAINER_ID"],
                port=int(os.environ["TEST_POSTGRES_PORT"]),
                runtime_password=os.environ["TEST_POSTGRES_PASSWORD"],
            )
            if (
                os.environ["APP_ENV"] != "test"
                or target.port == 0
                or os.environ["TEST_DATABASE_URL"] != target.url("runtime")
                or os.environ["DATABASE_URL"] != target.url("runtime")
            ):
                raise ValueError
        except (KeyError, ValueError):
            raise RunnerError(
                "Integration tests require the disposable runner; supplied URLs are never accepted."
            ) from None
        require_local_docker()
        target.verify_database("runtime")
        return target

    def cleanup(self):
        # Recover a successful create whose client timed out before returning its ID.
        if not self.container_id:
            matches = docker(
                "ps",
                "-aq",
                "--no-trunc",
                "--filter",
                f"name=^/{self.name}$",
                "--filter",
                f"label={LABEL}={self.run_id}",
            )
            if not matches:
                return
            self.container_id = matches
        self.verify_container(check_port=False)
        docker("rm", "--force", self.container_id)
        remaining = docker(
            "ps", "-aq", "--no-trunc", "--filter", f"id={self.container_id}"
        )
        if remaining:
            raise RunnerError(
                "Cleanup verification failed: owned container still exists."
            )
        print(
            f"Cleanup verified: container {self.container_id} absent; no volumes created.",
            flush=True,
        )


def exercise(target):
    try:
        target.create()
        target.bootstrap()
        target.migrate("upgrade", "head")
        target.verify_schema(True)
        target.grant_runtime()
        with tempfile.TemporaryDirectory(prefix="fitness-pg-pytest-") as temp:
            result = command(
                [
                    sys.executable,
                    "-m",
                    "pytest",
                    *PYTEST_OUTPUT_ARGS,
                    "-p",
                    "no:cacheprovider",
                    "--basetemp",
                    str(Path(temp) / "pytest"),
                    "integration_tests/postgres_cases.py",
                    "integration_tests/auth_cases.py",
                ],
                env=target.test_environment(),
                timeout=120,
                check=False,
            )
        output = result.stdout + result.stderr
        # Even assertion output must not disclose generated secrets.
        for kind in ("admin", "migration", "runtime"):
            output = output.replace(target.url(kind), "[redacted]").replace(
                getattr(target, f"{kind}_password"), "[redacted]"
            )
        print(output, flush=True)
        if result.returncode:
            raise RunnerError(
                "PostgreSQL integration tests failed; see counts above. Detailed diagnostics are suppressed to protect credentials."
            )
        target.migrate("downgrade", "base")
        target.verify_schema(False)
        target.migrate("upgrade", "head")
        target.verify_schema(True)
        print(
            "Migration round-trip passed: upgrade/head, downgrade/base, re-upgrade/head.",
            flush=True,
        )
    finally:
        target.cleanup()


def main():
    try:
        # Only this subprocess's environment changes; the invoking shell is untouched.
        sanitized = clean_environment()
        for key in tuple(os.environ):
            if key not in sanitized:
                del os.environ[key]
        require_local_docker()
        # Pull is bounded and occurs before any resources needing cleanup are created.
        docker("pull", IMAGE, timeout=300)
        digest = docker(
            "image", "inspect", IMAGE, "--format", "{{index .RepoDigests 0}}"
        )
        print(f"Test image: {digest}", flush=True)
        exercise(Target())
        return 0
    except (Exception, KeyboardInterrupt) as error:
        message = str(error) if isinstance(error, RunnerError) else type(error).__name__
        print(f"Disposable PostgreSQL tests failed: {message}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
