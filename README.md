# FitArena
### AI-Powered Competitive Fitness Platform

**FitArena** is a mobile fitness application that uses AI-powered pose detection to track workouts and lets friends compete in multiplayer fitness challenges.

Built as a Computer Science graduation project.

## Features

- **AI Workout Tracking:** Real-time pose detection using MediaPipe and CameraX.
- **Four Exercises:** Squats, Push-ups, Jumping Jacks, and Plank.
- **Rep Counting:** Automatic counting for repetition-based exercises.
- **Plank Timer:** Tracks valid hold duration.
- **User Authentication:** Register and log in with FastAPI and JWT.
- **Multiplayer Rooms:** Create or join private challenges using room codes.
- **Leaderboards:** Compare scores and rankings with friends.
- **Workout History:** Store exercise results in PostgreSQL.
- **FitArena Branding:** Custom app icon, splash screen, and responsive Flutter UI.

> **MVP note:** Exercise results are reported by the mobile device and are not independently verified against cheating. Very fast movements may occasionally be missed.

## Tech Stack

| Layer | Technologies |
|---|---|
| Mobile | Flutter, Dart |
| Pose Detection | MediaPipe, CameraX, Kotlin |
| Backend | Python, FastAPI |
| Database | PostgreSQL |
| Database Migrations | Alembic |
| Authentication | JWT |
| Development Infrastructure | Docker Desktop |
| Testing | Flutter Test, Pytest |

## Project Structure

```text
competitive-fitness-ai/
├── apps/
│   └── mobile/              # Flutter Android application
├── services/
│   └── backend/             # FastAPI backend
├── packages/
│   ├── contracts/           # API contracts
│   └── exercise_engine/     # Reference exercise engine
├── scripts/                 # Backend launch scripts
├── tools/
│   └── pose_lab/            # Offline exercise evaluation
├── docs/                    # Architecture documentation
├── ml/                      # ML research
└── README.md
```

## Requirements

Install the following before starting:

- Git
- Docker Desktop (Linux containers enabled)
- Python 3.12 or 3.13
- Flutter SDK
- Android Studio / Android SDK
- Android phone with USB Debugging enabled

For multiplayer testing, connect the backend computer and all mobile devices to the same trusted Wi-Fi network.

## 1. Clone the Repository

```powershell
git clone YOUR_GITHUB_REPOSITORY_URL
cd competitive-fitness-ai
```

Open PowerShell in the project root for the backend commands.

## 2. Set Up PostgreSQL with Docker

Start **Docker Desktop**.

For a completely new installation, create a PostgreSQL container.

Generate a development database password:

```powershell
$pgPassword = [guid]::NewGuid().ToString("N")
```

Create the database:

```powershell
docker run -d `
  --name fitness-db `
  -e POSTGRES_DB=fitness `
  -e POSTGRES_USER=fitness `
  -e "POSTGRES_PASSWORD=$pgPassword" `
  -p 127.0.0.1:5432:5432 `
  -v fitness-db-data:/var/lib/postgresql/data `
  postgres:17
```

**Important:** Run this creation command only once, on a fresh setup. If `fitness-db` or `fitness-db-data` already exists, do not recreate or delete it.

Check the database:

```powershell
docker exec fitness-db pg_isready -U fitness -d fitness
```

Expected output:

```text
/var/run/postgresql:5432 - accepting connections
```

The named Docker volume keeps database data between container restarts.

## 3. Configure Backend Environment

Create:

```text
services/backend/.env.local
```

Generate a JWT signing secret with Python:

```powershell
py -3.12 -c "import secrets; print(secrets.token_hex(48))"
```

If using Python 3.13, replace `-3.12` with `-3.13`.

Add the following environment variables:

```dotenv
APP_ENV=development
DATABASE_URL=postgresql+psycopg://fitness:YOUR_DB_PASSWORD@127.0.0.1:5432/fitness
JWT_SECRET=YOUR_GENERATED_RANDOM_SECRET
JWT_ISSUER=competitive-fitness-local
JWT_AUDIENCE=competitive-fitness-mobile
JWT_ALGORITHM=HS256
ACCESS_TOKEN_TTL_SECONDS=900
```

Replace the placeholders with the real credentials generated locally. URL-encode any special characters in the database password.

**Never upload `.env.local` to GitHub or share passwords and JWT secrets.**

For an existing installation, keep the original `.env.local` and database credentials.

## 4. Install Backend Dependencies

From the repository root:

```powershell
cd services/backend

py -3.12 -m venv .venv

& .\.venv\Scripts\python.exe -m pip install `
  -e ../../packages/contracts `
  -e ".[dev]"

cd ../..
```

Python 3.13 can also be used if 3.12 is unavailable.

If `.venv` already exists and works, reuse it rather than recreating it.

## 5. Initialize Database Tables

On the first installation, run the database migrations:

```powershell
.\scripts\run-backend-lan.ps1 -Migrate
```

Review the migrations and back up any existing database before upgrading it.

## 6. Start the Backend Server

Start Docker Desktop and ensure PostgreSQL is running:

```powershell
docker start fitness-db
```

Skip this command if the container is already running.

Start FastAPI:

```powershell
.\scripts\run-backend-lan.ps1
```

Keep the PowerShell window open.

The API runs on port **8000**.

Test the server from another PowerShell terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/v1/health
```

Expected response:

```json
{"status":"ok"}
```

## 7. Find the Backend IP Address

The IP address can change whenever the computer reconnects to Wi-Fi.

Find the current address:

```powershell
$pcIP = (Get-NetIPAddress `
  -InterfaceAlias "Wi-Fi" `
  -AddressFamily IPv4).IPAddress |
  Select-Object -First 1

Write-Host $pcIP
```

Example:

```text
192.168.1.100
```

Test the server using that IP:

```powershell
Invoke-RestMethod "http://${pcIP}:8000/api/v1/health"
```

Open the same URL in each phone's browser.

If the connection is blocked, check Windows Firewall and make sure devices are connected to the same trusted Wi-Fi network.

**Do not use `localhost` as the API URL on a mobile device.**

## 8. Run the Flutter Application

Open another PowerShell terminal.

Navigate to the Flutter project:

```powershell
cd apps/mobile
```

Install dependencies:

```powershell
flutter pub get
```

List connected devices:

```powershell
flutter devices
```

Run the application:

```powershell
flutter run -d DEVICE_ID --debug `
  --dart-define="FITNESS_API_BASE_URL=http://PC_IP:8000"
```

Replace `DEVICE_ID` with your Android device ID and `PC_IP` with the current backend computer IP.

Example:

```powershell
flutter run -d DEVICE_ID --debug `
  --dart-define="FITNESS_API_BASE_URL=http://192.168.1.100:8000"
```

The backend computer must stay running while testing multiplayer features.

## 9. Build an APK for Other Phones

From `apps/mobile`:

```powershell
flutter build apk --debug `
  --dart-define="FITNESS_API_BASE_URL=http://PC_IP:8000"
```

APK location:

```text
apps/mobile/build/app/outputs/flutter-apk/app-debug.apk
```

Install the APK on another Android phone.

All players must connect to the same backend URL to see the same rooms and scores.

**Note:** Local HTTP is supported for development/debug testing on trusted networks. A production deployment requires HTTPS and additional security hardening.

## 10. Test Multiplayer Challenges

1. Open FitArena on two Android phones.
2. Register a different account on each phone.
3. On Phone A, open **Challenges** and create a room.
4. On Phone B, join the room using its invitation code.
5. The room owner starts the challenge.
6. Each player performs an exercise and finishes the workout.
7. Check that the workout result is successfully submitted to the room.
8. Open the room leaderboard to compare exercise totals and overall rankings.

The room supports up to 12 players.

**Scoring:** Repetition-based exercises use total reps, while Plank uses hold duration. Overall ranking uses placement points rather than directly adding reps and seconds.

The leaderboard updates after successful workout submission.

## 11. Run Tests

Flutter tests:

```powershell
cd apps/mobile

flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug
```

Backend tests:

```powershell
cd services/backend

& .\.venv\Scripts\python.exe -m pytest -q
```

Run these commands from their respective directories.

## Troubleshooting

| Problem | Solution |
|---|---|
| `No pubspec.yaml found` | Run Flutter commands from `apps/mobile` |
| Docker connection error | Start Docker Desktop |
| PostgreSQL connection timeout | Check that `fitness-db` is running |
| Invalid JWT secret | Generate a new random secret of at least 32 bytes |
| Mobile cannot reach backend | Verify current PC IP, Wi-Fi and Windows Firewall |
| Room scores not updating | Confirm room is active and workout submission succeeded |
| Token expired | Log in again |
| Android build rejects `.png.bak` | Move backup files outside `android/app/src/main/res` |

## Current MVP Limitations

- Exercise results are not independently verified against cheating.
- Very fast push-ups and some squat variations may not be detected reliably.
- Login tokens currently expire after 15 minutes.
- Local multiplayer requires devices to reach the same backend server.
- Production deployment needs HTTPS, token renewal and security hardening.

## Team Workflow

- Create a feature branch for new work.
- Run tests before submitting changes.
- Never commit `.env.local`, credentials, build outputs, recordings, or local backups.
- Open a Pull Request before merging changes into `main`.
- Do not upload unlicensed model files or private fitness data.

## Official Documentation

- [Flutter Documentation](https://docs.flutter.dev/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Docker Documentation](https://docs.docker.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [GitHub Documentation](https://docs.github.com/)

---

**FitArena — Train. Compete. Improve.**