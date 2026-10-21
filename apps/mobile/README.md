# Competitive Fitness mobile

Material 3 Android-first MVP UI. All interactions are local mocks; no authentication,
backend, camera, inference, permissions or WebSockets are connected. No packages
were added. Use made-up credentials in demo forms.

## Run and check

From `apps/mobile`, with the existing Flutter SDK and dependencies:

```powershell
flutter emulators --launch Small_Phone
flutter run -d emulator-5554 --no-pub
flutter analyze --no-pub
flutter test --no-pub
dart format --output=none --set-exit-if-changed lib test
```

Device IDs may differ; inspect `flutter devices`. If dependencies are absent, run
`flutter pub get` first. Small_Phone uses 720x1280 physical pixels at density 320
(360x640 logical pixels). Widget coverage also uses 320x568 and 200% text size.

## Demo flow

- Welcome -> Log in / Create account / Explore demo -> Home.
- Forms validate v1 username/password rules locally; registration confirms the
  password. Submission shows loading then opens the demo. It creates no identity;
  credentials are neither sent nor saved.
- Home -> Start workout -> Squat or Push-up -> Preparation -> Practice -> Summary.
- Add mock rep increments a local counter. Pause disables reps and stops the timer.
  Backgrounding pauses automatically and requires explicit resume. Finish shows a
  temporary summary. Back confirms before discarding; cancel leaves practice paused.
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
2. Create/complete server WorkoutSession objects. Replace mock taps with native
   exercise-engine RepEvent output and ordered, idempotent submissions. The display
   timer uses whole foreground seconds, not the monotonic capture clock required
   for pose/rep timestamps.
3. Replace the camera-off card with native Android capture after the MediaPipe spike.
   Render FormFeedback codes/severity from the engine. No form assessment or accuracy,
   calorie or form-score claims are made by this UI.
4. Replace fixture loads with member-scoped challenge REST data; implement joining
   and creation against the server lifecycle. There is no local score-write operation.
5. Apply newer ScoreUpdate snapshots by revision; never add snapshot totals. Accepted
   scores remain server-authoritative. Joining/live updates are descriptive placeholders.
6. Add server-backed history and restoration. State currently resets on restart;
   leaving unfinished practice discards it after confirmation.
