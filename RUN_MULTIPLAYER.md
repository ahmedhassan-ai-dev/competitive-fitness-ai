# FEATURE-003A — Friends Rooms (Android + FastAPI + PostgreSQL)

## MVP delivered

- Actual account registration/login against configured FastAPI API (not just demo mode).
- Private friend rooms for 2–12 users, ten-character invite codes, owner-only start/finish.
- Multi-device scoreboards: totals by exercise + overall *placement points*, auto-refresh every 4 seconds.
- Users complete a real tracked workout, review their result, and explicitly tap **Submit to room**. Backend checks room membership, workout ownership, room start time, and single-use submission.
- Each submitted workout remains **unverified, device-reported**: this is suitable for a *friendly demo* but **not a cheat-resistant prize leaderboard**.
- Local no-API demo mode remains available. Front/rear camera and rep engine are unchanged.

## 0. Preflight

Run from repository root:

```powershell
& "$env:USERPROFILE\Desktop\feature-003a-rooms\apply-feature.ps1" -RepoRoot (git rev-parse --show-toplevel).Trim() -CheckOnly
```

Apply only on success; the package validates expected files and backs up replacements. It **never** deletes local MediaPipe model assets or untracked changes.

## 1. PostgreSQL server

You need an actual reachable PostgreSQL database. Use an existing local PostgreSQL installation or, if you have Docker Desktop, start a disposable local development instance with a persistent volume:

```powershell
$pgPassword = Read-Host 'Choose a development database password'
docker run --name fitness-db -e POSTGRES_DB=fitness -e POSTGRES_USER=fitness -e POSTGRES_PASSWORD=$pgPassword -p 127.0.0.1:5432:5432 -v fitness-db-data:/var/lib/postgresql/data -d postgres:17
```

If the container already exists, use `docker start fitness-db` rather than creating it again. Set the `.env.local` `DATABASE_URL` username/database to `fitness` and percent-encode the password as needed. Existing PostgreSQL installations are fine too. The initial development account must be allowed to run migrations; use a more restricted runtime user in production. **Do not** paste database credentials or JWT secrets into chat or commit them. Docker environment variables are visible to local Docker administrators, so this setup is **local development only**.

In `services/backend`, create `.env.local` (the project's `.gitignore` excludes it) containing these keys:

```dotenv
APP_ENV=development
DATABASE_URL=postgresql+psycopg://DB_USER:URL_ENCODED_PASSWORD@127.0.0.1:5432/fitness
JWT_SECRET=REPLACE_ME_WITH_A_LONG_RANDOM_SECRET
JWT_ISSUER=competitive-fitness-local
JWT_AUDIENCE=competitive-fitness-mobile
JWT_ALGORITHM=HS256
ACCESS_TOKEN_TTL_SECONDS=900
```

Generate `JWT_SECRET` locally with:

```powershell
py -3.12 -c "import secrets; print(secrets.token_urlsafe(48))"
```

Use the output only in `.env.local`. PostgreSQL must already be running and the database created. Passwords with `@`, `#`, `/` etc. must be URL encoded in `DATABASE_URL`. Do not open PostgreSQL port 5432 on the LAN: only the backend PC accesses it locally.

## 2. Backend dependencies and migration

```powershell
$repo = (git rev-parse --show-toplevel).Trim()
cd (Join-Path $repo 'services/backend')
& .\.venv\Scripts\python.exe -m pip install -e ../../packages/contracts -e '.[dev]'
& .\.venv\Scripts\python.exe -m pytest -q tests/test_room_routes.py tests/test_workout_routes.py tests/test_migration_definitions.py
```

Backup your database before applying the migration. Inspect `alembic/versions/0003_challenge_rooms.py`, then opt in explicitly:

```powershell
cd $repo
& .\scripts\run-backend-lan.ps1 -Migrate
```

This applies the existing revisions 0001 and 0002 if necessary, plus the new 0003. It does **not** apply migrations silently during server startup.

## 3. Run the API on your LAN

In a new PowerShell terminal, from the repo root:

```powershell
& .\scripts\run-backend-lan.ps1
```

Keep it open. Use another terminal to discover your PC's Wi-Fi IPv4 address:

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -match 'Wi-Fi|Ethernet' -and $_.IPAddress -notmatch '^169\.' } | Select-Object InterfaceAlias, IPAddress
```

Example: if PC IPv4 is `192.168.1.25`, from **each phone's browser** open:

`http://192.168.1.25:8000/api/v1/health`

It must respond `{"status":"ok"}`. `127.0.0.1` on the phone means the phone itself, not your PC. Keep the PC and phones on the same trusted network; avoid guest Wi-Fi/client isolation. If Windows Firewall blocks port 8000, allow the **private network only** (not public internet), preferably limited to your local subnet. Do not forward port 8000 from your router.

## 4. Run the same client on each phone

From `apps/mobile` (the actual Flutter project):

```powershell
cd (Join-Path $repo 'apps/mobile')
flutter test --no-pub
flutter build apk --debug --dart-define=FITNESS_API_BASE_URL=http://192.168.1.25:8000
flutter run -d R58R71XQY3J --debug --dart-define=FITNESS_API_BASE_URL=http://192.168.1.25:8000
```

Replace the sample IP with your actual PC IP. `--dart-define` becomes part of that build: installing a *previous* APK will still point at an older URL. For other Android phones, use their own `flutter run -d DEVICE_ID ...` or install the freshly built APK at `build/app/outputs/flutter-apk/app-debug.apk` (same `--dart-define` IP). Disable cellular data for initial tests if the phone switches networks.

Only the `debug` Android manifest permits cleartext HTTP. **Release builds must use an HTTPS URL and a trusted certificate.** The client intentionally refuses release HTTP. The backend must be deployed as a reachable service with PostgreSQL and TLS before remote friends on different networks can join; merely changing the phone IP won't work across the internet.

## 5. End-to-end flow (2 phones)

1. On phone A choose **Create account** (e.g. `alice_fitness`; password 12+ chars), and on phone B create a distinct account (`bob_fitness`).
2. A opens **Challenges → Create room**, copies the ten-character code. B chooses **Join with code**.
3. A sees 2 players and presses **Start room**.
4. Both phones tap one of four exercise chips, finish the workout, then **Submit to room** from the summary. Both see updated per-exercise scores and overall rankings within ~4 seconds of a successful submission.
5. Repeat for other exercises; room totals accumulate. A may **Finish competition**. Submissions then close. Start a fresh room to compete again.

Try a bad invite code, two repeated taps on Submit, duplicate workout submission, non-owner Start/Finish, and network interruption. Reopening the app currently requires logging in again; the MVP stores JWT only in memory. JWT expires after 15 minutes; sign in again before continuing. See next-phase notes below.

## API contract

All `/api/v1/rooms*` and `/api/v1/workouts` endpoints require `Authorization: Bearer <access_token>`.

| Method | Path | Description |
|---|---|---|
| POST | `/api/v1/auth/register` | Create account and receive JWT |
| POST | `/api/v1/auth/token` | Login and receive JWT |
| POST | `/api/v1/rooms` | Create private room, creator joins |
| GET | `/api/v1/rooms` | List rooms of signed-in account |
| POST | `/api/v1/rooms/join` | Join via invite code |
| GET | `/api/v1/rooms/{id}` | Room / leaderboard snapshot |
| POST | `/api/v1/rooms/{id}/start` | Owner starts, requires 2+ players |
| POST | `/api/v1/rooms/{id}/finish` | Owner closes |
| POST | `/api/v1/workouts` | Save tracked, unverified device result |
| POST | `/api/v1/rooms/{id}/submissions` | Reference owned workout ID once |

Example create body: `{"title":"Our weekend battle","max_players":8}`. Join body: `{"invite_code":"ABCD234567"}`. Submission body: `{"workout_id":"<server-issued UUID>"}`. For standings, `members[].exercises` holds four rows `{exercise,metric,total,sessions,rank}`; `members[].total_points` and `members[].overall_rank` provide the overall placement board. Plank `total` is in **milliseconds**, displayed as seconds in Flutter.

## Known limitations / next packages

- Device-reported scores aren't authoritative; don't offer cash prizes or anti-cheat claims. Validation of landmarks/event evidence and server-side scoring needs its own design.
- Auto-refresh polls every 4 seconds; it updates after a workout is **submitted**, not every rep live. WebSocket events and in-workout live scores are next-stage work.
- JWT access token expires in 900 seconds, no refresh token/persistent secure storage yet. Add refresh tokens, session revocation, secure token storage, rate limits and observability before production use.
- For testing on **different networks**, deploy FastAPI via HTTPS (trusted certificate, reverse proxy, no exposed DB), configure release URL, then run load/network tests. The LAN HTTP setting is development-only.
- Room creation/invite abuse controls, admin moderation, pagination, owner transfer, deletion, tamper-resistant verification and accessibility audits are separate tasks.

## Official references

- https://fastapi.tiangolo.com/deployment/
- https://www.uvicorn.org/settings/
- https://developer.android.com/training/articles/security-config
- https://alembic.sqlalchemy.org/en/latest/tutorial.html
- https://docs.flutter.dev/deployment/android
