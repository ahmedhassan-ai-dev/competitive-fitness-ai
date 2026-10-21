# Architecture baseline — ADR-001

**Decision:** modular FastAPI backend + on-device Android AI + Flutter + PostgreSQL.

**Why:** reliable end-to-end slice during a 14-day sprint, while allowing independent work streams.

**Data flow:** camera -> MediaPipe landmarks -> normalized features -> exercise-specific state machine/form rules -> rep event -> backend validation -> persistent score -> WebSocket broadcast.

**Caveat:** mobile native MediaPipe integration must be confirmed in the first 24 hours; Python `exercise_engine` serves as an offline reference only. Client-submitted rep results are not cryptographic proof of exercise correctness.
