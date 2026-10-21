# Shared contracts

Before implementing challenge or rep event ingestion, approve schemas for:
- `PoseFrame` (33 MediaPipe landmarks, timestamps, missing-pose states)
- `RepEvent` (`event_id`, `session_id`, `sequence`, `valid`, `form_score`, `errors`, `model_version`)
- Challenge REST API and WebSocket event names.

Contracts are currently design placeholders, not validated production schemas. Changes need review from AI, Flutter and Backend owners.
