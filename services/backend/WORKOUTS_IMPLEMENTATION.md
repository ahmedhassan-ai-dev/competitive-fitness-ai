# Exercise catalog and workout-history API — FEATURE-002A

## Live endpoints (configured application only)

- `GET /api/v1/exercises` — catalog with `id`, `metric`, suggested view and whether challenges are enabled.
- `POST /api/v1/workouts` — create a **device-reported** completed workout (requires Bearer JWT).
- `GET /api/v1/workouts?limit=30` — authenticated user's recent completed workouts (limit 1–100).

Configured FastAPI factory: `app.main:create_configured_app`; do **not** deploy `app.main:app` (health-only).

### Example POST

`Authorization: Bearer <access-token>`

```json
{"exercise":"jumping_jack","reps":20,"active_ms":40000}
```

```json
{"exercise":"plank","reps":0,"hold_ms":28000,"active_ms":32000}
```

Do not use these results as competitive scores. These records are *client-reported*: the app currently has local/demo authentication and does **not** submit workouts to these routes yet. Challenge eligibility remains **disabled** for all catalog entries until the backend verifies rep/hold events and enforces anti-replay, ownership, and challenge state.

### Database migration

This package adds `alembic/versions/0002_workout_records.py`. On a backed-up and reviewed PostgreSQL deployment, from `services/backend`:

```powershell
python -m alembic -x allow_database_migration=true upgrade head
```

Never run downgrade without backup and explicit review: it drops history.

### Developer verification

```powershell
cd services/backend
python -m pip install -e ".[dev]"
python -m pytest -q tests/test_workout_routes.py tests/test_migration_definitions.py
```

There is no client synchronization yet. Future FEATURE-002B should connect real login/JWT, submit an idempotent workout with retry logic, implement workout history in Flutter, and eventually server-validated Challenge score events. Avoid silently trusting a local demo sign-in.
