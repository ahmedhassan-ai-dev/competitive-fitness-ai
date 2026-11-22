import secrets
import subprocess
import sys
from unittest.mock import Mock

import pytest
from testing import postgres


def owned_target():
    target = postgres.Target(container_id="a" * 64, port=15432)
    info = {
        "id": target.container_id,
        "name": f"/{target.name}",
        "labels": {postgres.LABEL: target.run_id},
        "mounts": [{"Type": "tmpfs", "Destination": "/var/lib/postgresql/data"}],
        "ports": {"5432/tcp": [{"HostIp": "127.0.0.1", "HostPort": "15432"}]},
    }
    return target, info


def test_environment_discards_developer_configuration(monkeypatch):
    for key in (
        "DATABASE_URL",
        "TEST_DATABASE_URL",
        "PGHOSTADDR",
        "PGSERVICE",
        "PGPASSWORD",
        "JWT_SECRET",
        "APP_ENV",
        "PYTEST_ADDOPTS",
    ):
        monkeypatch.setenv(key, "must-not-be-used")
    target, _ = owned_target()
    env = target.test_environment()
    assert "must-not-be-used" not in env.values()
    assert env["DATABASE_URL"] == env["TEST_DATABASE_URL"] == target.url("runtime")
    assert env["APP_ENV"] == "test"
    assert "PGHOSTADDR" not in env and "JWT_SECRET" not in env
    assert target.runtime_password not in repr(target)
    assert target.runtime_password != postgres.Target().runtime_password


def test_missing_disposable_environment_rejects_supplied_url(monkeypatch):
    monkeypatch.delenv("TEST_POSTGRES_RUN_ID", raising=False)
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://localhost/development")
    connect = Mock(side_effect=AssertionError("Must reject before connecting"))
    monkeypatch.setattr(postgres.psycopg, "connect", connect)
    with pytest.raises(postgres.RunnerError, match="disposable runner"):
        postgres.Target.from_test_environment()
    connect.assert_not_called()


@pytest.mark.parametrize(
    "mismatch", ["id", "name", "label", "port", "host", "volume", "missing_mount"]
)
def test_container_mismatch_fails_before_database_access(monkeypatch, mismatch):
    target, info = owned_target()
    if mismatch in {"id", "name"}:
        info[mismatch] = "unrelated"
    elif mismatch == "label":
        info["labels"] = {}
    elif mismatch == "volume":
        info["mounts"][0]["Type"] = "volume"
    elif mismatch == "missing_mount":
        info["mounts"] = []
    else:
        info["ports"]["5432/tcp"][0]["HostPort" if mismatch == "port" else "HostIp"] = (
            "15433" if mismatch == "port" else "0.0.0.0"
        )
    monkeypatch.setattr(target, "inspect", lambda _: info)
    connect = Mock()
    monkeypatch.setattr(target, "connect", connect)
    with pytest.raises(postgres.RunnerError):
        target.verify_database("runtime")
    connect.assert_not_called()


def test_database_identity_mismatch_prevents_migration(monkeypatch):
    target, _ = owned_target()
    monkeypatch.setattr(target, "verify_container", Mock())
    connection = Mock()
    connection.execute.return_value.fetchone.return_value = ("development", "developer")
    context = Mock(
        __enter__=Mock(return_value=connection), __exit__=Mock(return_value=False)
    )
    monkeypatch.setattr(target, "connect", lambda _: context)
    command = Mock()
    monkeypatch.setattr(postgres, "command", command)
    with pytest.raises(postgres.RunnerError, match="identity mismatch"):
        target.migrate("upgrade", "head")
    command.assert_not_called()


def test_cleanup_targets_only_captured_id_and_verifies_absence(monkeypatch, capsys):
    target, info = owned_target()
    monkeypatch.setattr(target, "inspect", lambda _: info)
    docker = Mock(return_value="")
    monkeypatch.setattr(postgres, "docker", docker)
    target.cleanup()
    assert docker.call_args_list[0].args == ("rm", "--force", target.container_id)
    assert docker.call_args_list[1].args == (
        "ps",
        "-aq",
        "--no-trunc",
        "--filter",
        f"id={target.container_id}",
    )
    assert "Cleanup verified" in capsys.readouterr().out


def test_cleanup_refuses_foreign_ownership(monkeypatch):
    target, info = owned_target()
    info["labels"] = {}
    monkeypatch.setattr(target, "inspect", lambda _: info)
    docker = Mock()
    monkeypatch.setattr(postgres, "docker", docker)
    with pytest.raises(postgres.RunnerError, match="ownership mismatch"):
        target.cleanup()
    docker.assert_not_called()


def test_cleanup_recovers_id_after_create_timeout(monkeypatch):
    target, info = owned_target()
    target.container_id = ""
    docker = Mock(side_effect=[info["id"], "", ""])
    monkeypatch.setattr(postgres, "docker", docker)
    monkeypatch.setattr(target, "inspect", lambda _: info)
    target.cleanup()
    assert docker.call_args_list[1].args == ("rm", "--force", info["id"])


@pytest.mark.parametrize("stage", ["create", "bootstrap", "migrate"])
def test_finally_cleanup_on_setup_or_migration_failure(monkeypatch, stage):
    target = postgres.Target()
    for name in ("create", "bootstrap", "migrate"):
        monkeypatch.setattr(
            target,
            name,
            Mock(
                side_effect=postgres.RunnerError("synthetic") if name == stage else None
            ),
        )
    cleanup = Mock()
    monkeypatch.setattr(target, "cleanup", cleanup)
    with pytest.raises(postgres.RunnerError, match="synthetic"):
        postgres.exercise(target)
    cleanup.assert_called_once()


def test_unavailable_docker_and_timeout_hide_raw_diagnostics(monkeypatch):
    for failure in (
        FileNotFoundError("sensitive-output"),
        subprocess.TimeoutExpired(["secret"], 1),
    ):
        monkeypatch.setattr(subprocess, "run", Mock(side_effect=failure))
        with pytest.raises(postgres.RunnerError) as error:
            postgres.docker("version")
        assert "secret" not in str(error.value) and "sensitive-output" not in str(
            error.value
        )


@pytest.mark.parametrize("endpoint", ["tcp://remote:2375", "ssh://remote"])
def test_remote_docker_context_rejected(monkeypatch, endpoint):
    monkeypatch.delenv("DOCKER_HOST", raising=False)
    monkeypatch.setattr(postgres, "docker", Mock(return_value=endpoint))
    with pytest.raises(postgres.RunnerError, match="remote"):
        postgres.require_local_docker()


def test_legacy_tmpfs_metadata_accepted(monkeypatch):
    target, info = owned_target()
    info["mounts"] = []
    info["tmpfs"] = {"/var/lib/postgresql/data": "rw,size=512m"}
    monkeypatch.setattr(target, "inspect", lambda _: info)
    target.verify_container()


def test_readiness_timeout_is_bounded_and_cleanup_runs(monkeypatch):
    target, _ = owned_target()
    monkeypatch.setattr(postgres, "docker", Mock(return_value=target.container_id))
    monkeypatch.setattr(target, "verify_container", Mock())
    monkeypatch.setattr(
        target,
        "verify_database",
        Mock(side_effect=postgres.psycopg.OperationalError("unavailable")),
    )
    monkeypatch.setattr(postgres.time, "monotonic", Mock(side_effect=[0, 61]))
    sleep = Mock()
    monkeypatch.setattr(postgres.time, "sleep", sleep)
    cleanup = Mock()
    monkeypatch.setattr(target, "cleanup", cleanup)
    with pytest.raises(postgres.RunnerError, match="within 60 seconds"):
        postgres.exercise(target)
    cleanup.assert_called_once()
    sleep.assert_not_called()


def test_connection_does_not_set_empty_libpq_service(monkeypatch):
    target, _ = owned_target()
    connect = Mock()
    monkeypatch.setattr(postgres.psycopg, "connect", connect)
    target.connect("runtime")
    assert "service" not in connect.call_args.kwargs
    assert connect.call_args.kwargs["hostaddr"] == "127.0.0.1"


def test_cleanup_reports_container_still_present(monkeypatch):
    target, info = owned_target()
    monkeypatch.setattr(target, "inspect", lambda _: info)
    monkeypatch.setattr(postgres, "docker", Mock(side_effect=["", target.container_id]))
    with pytest.raises(postgres.RunnerError, match="still exists"):
        target.cleanup()


def test_test_failure_redacts_secrets_and_still_cleans_up(
    monkeypatch, capsys, tmp_path
):
    target, _ = owned_target()
    for name in ("create", "bootstrap", "migrate", "verify_schema", "grant_runtime"):
        monkeypatch.setattr(target, name, Mock())
    monkeypatch.setattr(postgres.tempfile, "tempdir", str(tmp_path))
    result = subprocess.CompletedProcess(
        [], 1, target.runtime_password, target.url("migration")
    )
    monkeypatch.setattr(postgres, "command", Mock(return_value=result))
    cleanup = Mock()
    monkeypatch.setattr(target, "cleanup", cleanup)
    with pytest.raises(postgres.RunnerError, match="integration tests failed"):
        postgres.exercise(target)
    output = capsys.readouterr().out
    assert "[redacted]" in output
    assert (
        target.runtime_password not in output
        and target.migration_password not in output
    )
    cleanup.assert_called_once()


def test_altered_test_url_rejected_before_docker_or_connection(monkeypatch):
    target, _ = owned_target()
    for key, value in target.test_environment().items():
        monkeypatch.setenv(key, value)
    monkeypatch.setenv(
        "TEST_DATABASE_URL", "postgresql+psycopg://localhost/development"
    )
    docker = Mock()
    monkeypatch.setattr(postgres, "docker", docker)
    with pytest.raises(postgres.RunnerError, match="supplied URLs are never accepted"):
        postgres.Target.from_test_environment()
    docker.assert_not_called()


@pytest.mark.parametrize("failure", ["assertion", "setup", "collection"])
def test_pytest_diagnostics_do_not_expose_generated_credentials(tmp_path, failure):
    marker = secrets.token_urlsafe(32)
    source = "import os, sys, warnings\nimport pytest\n"
    if failure == "collection":
        source += "raise RuntimeError(os.environ['PRIVATE_TEST_CANARY'])\n"
    elif failure == "setup":
        source += (
            "@pytest.fixture\ndef broken():\n"
            "    raise RuntimeError(os.environ['PRIVATE_TEST_CANARY'])\n"
            "def test_failure(broken): pass\n"
        )
    else:
        source += (
            "def test_failure():\n"
            "    value = os.environ['PRIVATE_TEST_CANARY']\n"
            "    print(value)\n    print(value, file=sys.stderr)\n"
            "    warnings.warn(value)\n    assert False, value\n"
        )
    case = tmp_path / "test_diagnostics.py"
    case.write_text(source, encoding="utf-8")
    config = tmp_path / "pytest.ini"
    config.write_text("[pytest]\n", encoding="utf-8")
    env = postgres.clean_environment()
    env.update(PRIVATE_TEST_CANARY=marker, PYTEST_DISABLE_PLUGIN_AUTOLOAD="1")
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            *postgres.PYTEST_OUTPUT_ARGS,
            "-p",
            "no:cacheprovider",
            "-c",
            str(config),
            str(case),
        ],
        env=env,
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=30,
    )
    leaked = marker in result.stdout or marker in result.stderr
    assert not leaked, "Pytest exposed a generated credential in failure output"
    assert result.returncode in (1, 2)
    assert "1 failed" in result.stdout or "1 error" in result.stdout


@pytest.mark.parametrize("failed_migration", [1, 2])
def test_round_trip_failure_propagates_and_cleans_up(
    monkeypatch, tmp_path, failed_migration
):
    target, _ = owned_target()
    for name in ("create", "bootstrap", "verify_schema", "grant_runtime"):
        monkeypatch.setattr(target, name, Mock())
    results = [None, None, None]
    results[failed_migration] = postgres.RunnerError("migration round-trip failed")
    migrate = Mock(side_effect=results)
    monkeypatch.setattr(target, "migrate", migrate)
    monkeypatch.setattr(postgres.tempfile, "tempdir", str(tmp_path))
    monkeypatch.setattr(
        postgres,
        "command",
        Mock(return_value=subprocess.CompletedProcess([], 0, "1 passed", "")),
    )
    cleanup = Mock()
    monkeypatch.setattr(target, "cleanup", cleanup)
    with pytest.raises(postgres.RunnerError, match="round-trip failed"):
        postgres.exercise(target)
    assert migrate.call_count == failed_migration + 1
    cleanup.assert_called_once()
