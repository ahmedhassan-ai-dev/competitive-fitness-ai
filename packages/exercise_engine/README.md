# Deterministic Python exercise reference — 1.0.0

`src/exercise_engine/engine.py` defines ExerciseEngine (Protocol), EngineOutput and
ReferenceEngine. `process(PoseFrame) -> EngineOutput` returns shared RepEvents and
immediate FormFeedback; `reset()` drops partial motion, retaining sequence and
last timestamp. One instance per session/exercise. Replaying identical frames
with the same session ID yields identical events, including UUIDv5(session_id,
`rep:{sequence}`) IDs. Never restart within a session without history replay:
sequence/IDs would repeat. There is no persistence/server acceptance here.

Backend pytest config adds repository root and `packages/exercise_engine/src`
to Python paths; standalone scripts must put both on PYTHONPATH. This is offline
Python, not directly executable on Android. Port interface/tests to native later.

## Normalization

PoseFrame contains timestamp_ms and named Landmark(x, y, confidence) values.
Squats require hip/knee/ankle; push-ups shoulder/elbow/wrist. No MediaPipe indices,
landmark count, inference runtime or camera are assumed. Use a consistent visible
anatomical side for the session and side view. Do not switch left/right joints.
Input must be upright, rotation-corrected, unmirrored, x right/y down. Use the same
coordinate scale on both axes: divide pixel x/y by max(image width, image height)
to preserve angles and remain in [0,1]. Independent axis normalization distorts
angles. Depth is ignored. Omit out-of-frame joints rather than clamp coordinates.
Confidence is visibility/presence in [0,1]; absent keys mean missing joints and an
empty dictionary means missing pose. NaN/Infinity are invalid.

timestamp_ms is capture time from a session-local monotonic clock, not processing
time. Duplicate/backward timestamps raise ValueError before changing state. A gap
>500 ms drops partial motion; the current frame may begin rearming. Missing joints,
confidence <0.8 or coincident joint geometry drop partial motion and emit
low_confidence feedback. The boundary 0.8 is inclusive. Rep confidence is the
minimum observed across the cycle.

## State transitions and hysteresis

Angle is measured at knee/elbow between adjacent joint vectors. Proposed rules,
pending held-out-user evaluation:

| Exercise | Top | Bottom |
| --- | --- | --- |
| squat | >=160 degrees | <=100 degrees |
| push_up | >=155 degrees | <=90 degrees |

States: unarmed -> top -> bottom -> top. Each transition requires consecutive
usable frames in the target band spanning >=100 ms (at least two frames). Leaving
the target band cancels its hold. Intermediate angles retain established phase
and cancel candidate holds. Sustained top arms; sustained bottom records depth;
sustained return to top emits exactly one rep. Starting at bottom, a single frame
crossing, stationary holds, shallow motion or partial returns never count.
The first interval starts at confirmed arming and ends at confirmed return;
subsequent intervals start at the previous end. No randomness or wall clock.

This reference emits completed valid range-of-motion reps and immediate tracking
feedback. Alignment assessment and rejected-attempt events are deferred; feedback
codes incomplete_range/body_alignment are reserved. form_score=1.0 means only that
this reference motion rule completed, not measured fitness/form quality. Viewpoint,
occlusion and projection may defeat the rules. No accuracy or anti-cheat claim;
server validation/authoritative scoring remain necessary.

`python -m pytest -q` from services/backend tests both movements, replay, multiple
cycles, jitter, partial motion, missing/low-confidence/degenerate joints, dropped
frames, reset, timestamps and shared contract compatibility, without camera/ML.
