# Competitive Fitness integration roadmap

## Delivered in FEATURE-002A

- `Squat` and `Push-up` legacy engines unchanged (protect current best baseline).
- Two *experimental* live pose-based exercises:
  - `jumping_jack`: counted closed → open → closed; front camera placement recommended, rear lens still default.
  - `plank`: counts only observed valid side-on hold intervals in milliseconds.
- Four exercise choices with per-exercise setup illustrations and measurement-specific Workout summary.
- FastAPI catalog and completed-workout-history endpoints, PostgreSQL model and reviewed Alembic migration.
- Unverified device-reported data explicitly marked as such; not authoritative challenge scores.

## Next FEATURE-002B (must be tested separately)

1. Replace demo-only authentication with real FastAPI JWT flow, session token handling, logout and expiration handling.
2. Add mobile API client with endpoint configuration (Android emulator `10.0.2.2`, physical phone must use reachable HTTPS host), authorization and secure token persistence.
3. Define idempotency key / upload retries for completion, exercise metric contract, offline pending history and cross-device sync.
4. Add History screen with grouped sessions and user-owned records, error/loading/empty states.
5. Test with real PostgreSQL in Docker and migrations, not just isolated unit tests.

## Then FEATURE-003 Challenges

1. Decide eligible exercises and scoring basis (reps vs verified hold milliseconds).
2. Persist challenge states and participants; enforce two distinct authenticated users.
3. Join, start, finish and cancel transitions with transactional guards and concurrency tests.
4. Server validates events before accepting scores; reject duplicate/replayed events.
5. Leaderboard and WebSocket/polling updates only from verified server-side results.
6. Keep existing mock challenge UI clearly labeled until real integration passes E2E tests.

## Performance note

Fast Push-up remains an open, device-specific tracking issue. This package intentionally does not modify `PoseCameraView.kt` or `pose_rep_counter.dart`. Benchmark/profile/replay improvements stay in LAB rather than risking the accepted Squat/Push-up baseline.
