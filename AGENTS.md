# Codex / AI agent instructions

## Mission
Build a robust, measurable, Android-first competitive fitness platform during a 14-day DEPI sprint. Prioritize a working vertical slice, small PRs, reproducibility and honest metrics.

## Architecture boundaries
- Flutter/Dart UI and camera live under `apps/mobile`.
- Native MediaPipe Android layer supplies pose frames; Python reference code is **not** directly executable on Android.
- Backend lives in `services/backend` and owns challenge membership, session state and accepted scores.
- Shared event schemas live in `packages/contracts`; changes require coordination and tests.
- Research/datasets/models belong in `ml` and must not be committed if large/private.

## Working rules
1. Inspect existing code and docs before editing; solve only the scoped issue.
2. Prefer built-in code and approved libraries, avoid new dependencies without reason.
3. Never hardcode credentials, commit `.env`, raw video, personal data, model weights or datasets.
4. Add or update tests for behavior; report exact commands executed and any tests not run.
5. Respect contract stability and follow SemVer when modifying external APIs.
6. Do not claim a measured model accuracy until validated on held-out users/clips.
7. Use clear feature branches, targeted diffs, and PRs. Do not push directly to main.
8. No potentially unsafe force push, deletion, external deployment, or migrations without explicit review.
9. For pose logic, document orientation, frame timestamps, confidence, and missing landmarks.
10. End each implementation task with: changed files, outcome, tests, limitations, next step.

## Initial acceptance gates
- Flutter Android skeleton builds on team test device.
- FastAPI health endpoint is testable and documented.
- Pose landmarks are extracted from a recorded sample.
- First rep event can be validated by contracts and accepted idempotently by the backend.
