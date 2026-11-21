# Competitive Fitness mobile

Material 3 Android-first MVP. Workout sessions can run on-device MediaPipe pose
tracking for squat and push-up reps. Authentication, backend workout/challenge
flows, accepted scores and WebSockets remain unconnected. No Flutter packages were
added; Android uses CameraX and MediaPipe Tasks.

## Run and check

From `apps/mobile`, with Flutter, Android SDK and JDK 17 installed:

```powershell
flutter emulators --launch Small_Phone
flutter run -d emulator-5554 --no-pub
flutter analyze --no-pub
flutter test --no-pub
dart format --output=none --set-exit-if-changed lib test
```

Device IDs may differ; inspect `flutter devices`. If Flutter dependencies are absent,
run `flutter pub get` first. The first camera session downloads the 5.8 MB MediaPipe
Pose Landmarker Lite model from Google over HTTPS, verifies its pinned SHA-256, and
caches it in app-private storage. It is not stored in this repository. Small_Phone
uses 720x1280 physical pixels at density 320
(360x640 logical pixels). Widget coverage also uses 320x568 and 200% text size.

## Demo flow

- Welcome -> Log in / Create account / Explore demo -> Home.
- Forms validate v1 username/password rules locally; registration confirms the
  password. Submission shows loading then opens the demo. It creates no identity;
  credentials are neither sent nor saved.
- Home -> Start workout -> Squat or Push-up -> Preparation -> Practice -> Summary.
- Camera permission is requested only after tapping Enable camera. Pose inference
  and rep counting run locally; frames are not uploaded or saved. The preview draws
  a body-joint skeleton when the selected joints are visible. The first use requires
  internet access to download the same MediaPipe Pose Landmarker Lite model used by
  the reference project. Counts use its flexion/extension thresholds; each deep
  bend counts once, and standing back up rearms the counter. Squats
  need the hip, knee and ankle in view; push-ups need the shoulder, elbow and wrist.
  Pause stops the camera and timer; resume requires explicitly enabling the camera
  again. Back confirms before discarding; cancel leaves practice paused.
- Rep counts and summaries are temporary local values, not server-validated scores.
  The counter does not assess form quality and has no held-out-user accuracy claim.
- Summary -> Back to home clears workout routes; Practice again starts fresh.
- Home/Challenges navigation opens sample waiting, active and completed rooms.
  Details show fixed accepted rep totals. Practice never changes challenge scores.
- In Challenges, Preview states selects samples, empty or simulated error. Empty
  and error views offer recovery; loading displays a progress indicator.
- Leave demo returns to Welcome and clears the navigation stack.

The starter counter remains at `/counter-demo`, or as a separate target:
`flutter run -t lib/features/demo/counter_demo.dart`. Its original smoke test keeps
its assertions and now mounts that screen explicitly.

## Structure

- `lib/app.dart`: Material 3 theme and app entry.
- `lib/shared/ui.dart`: responsive scrollable page, cards, headings, state messages
  and navigation helper. Content width is capped at 800 logical pixels; metric pairs
  stack on narrow screens or at enlarged text sizes. Safe areas and scrolling also
  accommodate the keyboard. Controls use built-in Material accessibility.
- `lib/features/auth`, `home`, `workouts`, `challenges`: feature screens and local
  widget state. No router or state management dependency.
- `lib/models/exercise_type.dart`: exact v1 wire values `squat`, `push_up` plus labels.
- `lib/data/mock_challenges.dart`: presentation fixtures named Challenge and
  ChallengeParticipant. They are not complete wire DTOs; do not serialize them as
  API requests.

## Integration points

`../../packages/contracts/v1` remains authoritative; wire version is 1.0.0.

1. Replace form delays with `/api/v1/auth/register` and `/auth/token`. Handle ApiError,
   expiry and secure token lifecycle without retaining passwords. Current success
   means opening a demo only.
2. Create/complete server WorkoutSession objects. Convert detected reps to shared
   RepEvent objects with session sequencing, then submit them in order with
   idempotent retries. The display timer uses whole foreground seconds, not the
   monotonic capture clock used for pose/rep timestamps.
3. Generate shared RepEvent objects and connect them to workout creation/submission.
   Current Android inference uses the upstream MediaPipe Lite model and emits
   normalized, upright image landmarks for both sides; the Dart counter fixes the
   most visible side for the session. The reference app thresholds are used
   (below 70 degrees at the bottom, above 160 degrees at the top); entering the
   bottom counts once, and returning to the top rearms the counter. Capture time is Android's
   monotonic elapsed-realtime clock in milliseconds. Out-of-frame landmarks are
   omitted; as in the reference script, visibility/presence scores do not gate
   angle-based counts. Missing pose frames do not rearm the counter. No server
   scores are sent.
4. Replace fixture loads with member-scoped challenge REST data; implement joining
   and creation against the server lifecycle. There is no local score-write operation.
5. Apply newer ScoreUpdate snapshots by revision; never add snapshot totals. Accepted
   scores remain server-authoritative. Joining/live updates are descriptive placeholders.
6. Add server-backed history and restoration. State currently resets on restart;
   leaving unfinished practice discards it after confirmation.
