# ADR-001: Android-first, local pose inference

Status: Accepted for prototype; revisit after Android spike.

- Flutter owns navigation and UI.
- Native Android MediaPipe performs pose inference (subject to technical spike).
- Python implementation is the test/reference implementation, not a mobile runtime.
- FastAPI handles identity, challenges, sessions and scores.
- PostgreSQL is persistent storage; real-time updates use WebSocket.
- No Kubernetes/microservices for initial 14-day sprint.
