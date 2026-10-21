# AI-Powered Competitive Fitness Platform

DEPI Microsoft Machine Learning graduation project — 14-day Android-first sprint, six-person team.

## Scope
- Android Flutter app (camera, workout, challenges, results)
- On-device MediaPipe pose estimation (native Android integration technical spike)
- Squat/push-up reference rep counting and measurable form feedback
- FastAPI backend (users, challenge rooms, workout event ingestion, scores)
- PostgreSQL and WebSocket live updates
- Offline Python ML research/training/evaluation

**Status:** foundation scaffold; no functional app or trained model is included yet.

## Architecture
- `apps/mobile`: Flutter project created via `flutter create --platforms android --project-name competitive_fitness_mobile .` in this directory
- `services/backend`: FastAPI service
- `packages/exercise_engine`: Python reference engine and tests (not directly executed in Flutter)
- `packages/contracts`: authoritative wire format schemas
- `ml`: datasets, experiments, training/evaluation; do not commit datasets or weights
- `docs`: decisions, reports, design notes

## Getting started (Windows / VS Code)
1. Install Git, Python 3.10+ (recommended 3.11), Flutter SDK, Android SDK and VS Code.
2. Open repository root in VS Code (`code .`).
3. Create Flutter skeleton: `cd apps/mobile; flutter create --platforms android --project-name competitive_fitness_mobile .; flutter doctor -v`.
4. Backend: `cd services/backend; py -3.11 -m venv .venv; .\.venv\Scripts\Activate.ps1; pip install -e ".[dev]"; python -m pytest; uvicorn app.main:app --reload`.
5. Root folder contains only scaffolding for the AI package; module functionality is Sprint 1 work.

## Team workflow
Read `CONTRIBUTING.md` and `AGENTS.md`. Every change: issue -> branch -> tests -> PR -> review -> merge. Keep main stable.
