# Task 002 — Flutter workout UI foundation

Date: 2026-10-21. Branch: feat/flutter-workout-ui.

## Outcome

Material 3 UI with Welcome, Login, Register, Home, exercise selection, preparation,
practice session, summary, challenge list and challenge details. Uses only Flutter
and existing dependencies. No auth, persistence, networking, camera or inference.

Mock reps are manual; the timer pauses in the background and requires explicit
resume. Paused practice disables reps. Back confirms discarding unfinished practice.
Completion stops the timer; retry starts fresh; returning home clears workout routes.
Challenge scores are fixed presentation fixtures and cannot be modified by practice.

Shared cards, headings and state messages give consistent loading, empty and error
views. Challenge Preview states makes all three testable without network access.
Scrollable safe-area layouts support narrow screens and keyboard insets; metric
pairs stack on narrow widths or with enlarged text. Content width caps at 800.
The welcome screen puts entry actions before its explanatory card for easier access.

## Changed files

Under `apps/mobile`:

- `lib/main.dart`: app entry and compatibility exports.
- `lib/app.dart`: theme, Welcome entry and retained counter-demo route.
- `lib/shared/ui.dart`: responsive page, cards, headings, states, navigation helper
  and elapsed-time formatting.
- `lib/models/exercise_type.dart`: Squat/Push-up labels and exact v1 wire values.
- `lib/data/mock_challenges.dart`: sample Challenge/ChallengeParticipant view data.
- `lib/features/auth/auth_screens.dart`: Welcome and local demo forms.
- `lib/features/home/home_screen.dart`: dashboard, tab navigation and leave-demo action.
- `lib/features/workouts/workout_screens.dart`: selection, preparation and summary.
- `lib/features/workouts/workout_session_screen.dart`: mock counter/timer and lifecycle.
- `lib/features/challenges/challenge_screens.dart`: state previews, sample list/details.
- `lib/features/demo/counter_demo.dart`: original starter counter retained verbatim.
- `test/widget_test.dart`: original smoke-test assertions retained; mounts the counter
  directly because the app now starts at Welcome.
- `test/workout_ui_test.dart`: primary navigation and interaction coverage.
- `README.md`: demo usage, structure and integration details.

Also added this report. No contracts, backend code, dependencies or Android build
configuration were edited. An unrelated working-tree edit appeared in the Task 001
report during this task and was left untouched.

## Validation

Commands from `apps/mobile`:

```powershell
dart format lib test
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter devices --machine
flutter emulators
flutter emulators --launch Small_Phone
flutter run -d emulator-5554 --no-pub --no-resident
```

Results: 13 tests passed, including the retained starter smoke test. Analyzer found
no issues. Dart formatting check passed. Small_Phone was launched; the Android
debug APK built, installed and ran. Welcome/dashboard screenshots were inspected
from temporary files outside the repository. No screenshots/build artifacts added.

Coverage includes form validation/confirmation/visibility and submission loading;
both exercises through summary/restart/home; rep counting, timer pause/resume;
background lifecycle; discard confirmation; challenge details, loading, empty/error
recovery and tab navigation; v1 exercise values; and 320x568 layouts at 100%/200%
text size. Registration is also tested at Small_Phone's 360x640 logical size with
200% text and a simulated keyboard inset.

The first test run caught a Future returned from a setState callback in challenge
reload, which was corrected. A later keyboard test required settling focus-driven
scrolling before tapping; final tests pass without missed-tap warnings. SDK/Android
cache access required running Flutter checks outside the filesystem sandbox.

From repository root: `git diff --check` checks patch whitespace. Backend/Python
tests were not rerun because no backend/contracts/engine files changed. Widget
tests cover flows; the emulator check is a build/launch and visual smoke check,
not a full device integration suite. No commit, push or merge performed.

## Remaining integration points and risks

- Presentation Challenge fixtures are not full wire DTOs. Add reviewed Dart v1 DTO
  parsing/semantic validation before REST integration; do not serialize view data.
- Replace local form delays with auth calls and ApiError handling; manage token
  expiry/storage. Demo submission currently establishes no identity.
- Create/complete server WorkoutSession objects. Replace mock taps with native
  RepEvents, retaining ordered/idempotent ingestion. Display time is approximate
  whole foreground seconds, not the monotonic capture clock used for pose frames.
- Replace the camera-off card with native capture and FormFeedback rendering after
  the Android pose spike. No form quality/accuracy/calorie claims are made.
- Load member-scoped challenges and implement create/join. Apply ScoreUpdate full
  snapshots only for newer revisions; server accepted scores remain authoritative.
- No history, process restoration, real invitations or live updates yet. Practice
  and summary are temporary. Rotate/resize layouts use Flutter's responsive widgets;
  exhaustive device/TalkBack testing remains follow-up work.

Next step: UI review on the team device, followed by the server-backed workout
vertical slice and native pose integration using the unchanged v1 contracts.