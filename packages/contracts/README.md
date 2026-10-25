# MVP contracts — 1.0.0

Shared baseline for Mobile, Backend and AI review. No routes, authentication,
storage or networking are implemented here. The health endpoint is unchanged.
Python models reuse Pydantic from FastAPI; Flutter/native consumers use JSON artifacts.

## Files and versioning

- `v1/models.py`: typed wire models and semantic validators.
- `v1/schemas.json`: generated JSON Schema 2020-12; select `#/$defs/RepEvent`, etc.
- `v1/openapi.json`: generated OpenAPI 3.1 REST request/response specification.
- `v1/examples.json`: representative synthetic JSON for every object model.
- `../exercise_engine/README.md`: pose normalization and state machine interface.

Regenerate at repository root: `python -m packages.contracts.v1.generate`.
Tests reject stale artifacts. REST/WS use `/api/v1`; events explicitly carry
`schema_version: "1.0.0"`. Breaking fields, enums or behavior require a major
version and parallel API path. Objects reject unknown keys, so wire additions
also require coordinated rollout and a version change. Review with Mobile,
Backend and AI owners before merge. This replaces design placeholders, not an
existing released API.

## Validation

IDs are UUID strings. Server timestamps are ISO-8601 UTC with timezone. Pose/rep
timestamps are nonnegative integer milliseconds on one session-local monotonic
clock, never wall-clock time. Sequences/revisions start at 1. Counts are nonnegative
integers, never booleans. Scores/confidence/coordinates are finite in [0,1].
ExerciseType is `squat | push_up`. Unknown keys are forbidden. Rep duration must
be positive; valid reps require confidence >=0.8. Feedback codes are
`low_confidence | incomplete_range | body_alignment`, severity `info | warning`.
Form scores are diagnostics, never points.

JSON Schema enforces structural rules and formats (enable format checking).
Python validators additionally enforce UTC-only timestamps, session time order
and lifecycle, distinct participants/sessions, rep duration/confidence and receipt
reason consistency. Dart/native validators must implement these semantic rules
too. Ownership, ordering, deduplication and membership require server state;
neither schema nor model validation establishes server acceptance.

## REST (prefix `/api/v1`)

| Method/path | Request | Success |
| --- | --- | --- |
| POST `/auth/register` | AuthRequest | 201 TokenResponse |
| POST `/auth/token` | AuthRequest | 200 TokenResponse |
| POST `/workouts` | CreateWorkout | 201 WorkoutSession |
| GET `/workouts/{session_id}` | none | 200 WorkoutSession |
| POST `/workouts/{session_id}/reps` | RepEvent | 200 RepReceipt |
| POST `/workouts/{session_id}/complete` | none | 200 WorkoutSession |
| POST `/challenges` | CreateChallenge | 201 Challenge |
| GET `/challenges/{challenge_id}` | none | 200 Challenge |
| POST `/challenges/{challenge_id}/join` | none | 200 Challenge |

Authentication uses JSON username/password. Usernames are unique, case-sensitive,
3–32 ASCII letters/digits/underscores; passwords are 12–128 characters. Register
creates a user and returns a token (duplicate username: 409); login returns a token
(incorrect credentials: 401). No refresh/logout in v1. Examples use dummy tokens.
Other routes require `Authorization: Bearer <token>`. The server derives user ID;
client request models cannot set user IDs or scores. Bodyless POSTs accept no body.

All errors use ApiError: 401 unauthorized (including expired credentials),
403 forbidden (wrong owner/nonmember), 404 not_found, 409 conflict (state/capacity/
ordering/changed retry), 422 validation_error (shape/semantic input). Future FastAPI
handlers must map default validation errors to this envelope.

## Lifecycle and authoritative scoring

Standalone creation returns an active session with server IDs and UTC started_at.
Only its owner can read, submit or complete. One exercise per session. Completion
is idempotent and sets ended_at >= started_at; active sessions have null ended_at.
New events after completion get 409.

Challenge creation makes a waiting room containing its creator (null session_id,
zero accepted_reps). Joining adds the second distinct user; repeat joins by members
are idempotent, a third user gets 409. Only members may read a challenge. After two
members join, each creates one workout with challenge_id and matching exercise;
repeat creation gets 409. The room becomes active atomically when both sessions
exist. Active/completed rooms require two distinct users with distinct non-null
sessions. Only active rooms accept new reps. Completion of both workouts completes
the challenge; the other participant may keep submitting until then. Waiting rooms
may have zero or one assigned session. Cancellation/timeouts are deferred.

Each server-accepted valid rep adds one point; ties are draws. form_score never
weights points. The backend checks identity, membership, exercise, state, sequence
and event semantics. Client validity/confidence are claims, not exercise proof.
There is no client score-write API.

event_id is the idempotency key within an authenticated session. Store event,
receipt and score mutation atomically. Exact retries return the original receipt
(including its original accepted_reps), even after completion; changed content
for the same ID gets 409. Retry lookup precedes lifecycle checks. Sequence must
start at 1 and be contiguous across all recorded events, including rejected reps.
Sequence reuse with a new ID or out-of-order events gets 409 without mutation.
Rep intervals cannot overlap: started_at_ms >= previous ended_at_ms. Path/body
session ID mismatch gets 422. Retry missing events before later events.

Well-formed invalid reps get a stored rejected receipt (`low_confidence` when
confidence <0.8, otherwise `invalid_rep`), consume sequence and add zero points.
Malformed events get 422 and consume nothing. Low-confidence claims must set
valid=false to satisfy the valid/confidence semantic rule.
Only accepted reps advance challenge revision/broadcast scores. Storage and
idempotency behavior are specified here, not implemented by this task.

## WebSocket

`/api/v1/challenges/{challenge_id}/scores` streams server-to-client ScoreUpdate JSON.
Native Android authenticates the upgrade with Authorization bearer header.
Require membership before upgrade: HTTP 401/403/404 on failure. After upgrade,
expired authentication closes with 1008, server failure with 1011. Unexpected
client data closes with 1008; reps use REST only.

Messages carry `type: "challenge.score_updated"`, schema_version, unique server
event_id, challenge_id, UTC occurred_at, per-challenge revision and a full snapshot
of both participants' accepted_reps. Revision 1 is the initial zero-score snapshot
when the challenge becomes active; each accepted rep increments it once. Waiting
rooms have no snapshot. On subscribe/reconnect send the latest active/completed
snapshot with its original revision/event_id. Delivery may duplicate/skip revisions;
replace totals only for a newer revision, discard older/equal ones, never sum.
GET challenge reconciles lifecycle and totals; v1 has no replay/cursor/completion
event. Publish after score commit; duplicate REST retries never create revisions.

## Verification

Install independently with `python -m pip install ./packages/contracts` from the
repository root. The distribution is `competitive-fitness-contracts==1.0.0`; Python
imports remain `packages.contracts.v1`. Wheels include JSON schemas/examples and
the exporter, without tests or exercise-engine code.

From `services/backend`, install `python -m pip install -e ../../packages/contracts -e ".[dev]"`, then:

```powershell
python -m pytest -q
python -m ruff check --config pyproject.toml app tests ../../packages/contracts ../../packages/exercise_engine
```

This includes existing health tests. jsonschema is a test-only dependency to verify
exported JSON independently of Pydantic. No mobile runtime dependency is added.
