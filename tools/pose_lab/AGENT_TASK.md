# Antigravity / coding agent task — MM-Fit adapter hardening

**Scope:** ONLY `tools/pose_lab/` and `apps/mobile/tool/pose_lab/` in a separate Git branch. Do not edit the live Android CameraX pipeline or `PoseRepCounter` in this task. Do not push, deploy, or upload any private recordings.

1. Inspect local MM-Fit filenames, first 2 label rows, and `.npy` dimensions **without altering them** using `python tools/pose_lab/mmfit_adapter.py inspect --root <DATASET_PATH>`.
2. Confirm exact keypoint order, axes, image coordinate scale, timestamp indexing and labels using the official MM-Fit helpers + inspected data. Never assume its keypoints equal MediaPipe's 33 landmarks.
3. Add validated mapping JSON with a test fixture from data the user has permission to share (or synthetic if unavailable). Preserve subject ID + camera/view metadata and separate person-disjoint train/test.
4. Convert Squat and Push-up labeled intervals to a manifest with independently verified count, optionally per-rep completion timestamps. **Do not invent per-rep timestamps from total count**.
5. Run the production Dart PoseRepCounter replay on converted frames and export aggregate CSV/JSON. Separate offline counter performance from actual MediaPipe detector performance on phone videos.
6. Unit-test non-monotonic timestamps, missing landmarks, rapid reps, camera angles, coordinate conversion, no pose. If mapping/labels cannot be validated, STOP and report the blocker instead of emitting synthetic accuracy.
7. Supply a reproducible command, sample logs and modifications as a Git diff. Do not merge experimental changes into main without a measured improvement and user approval.

Official sources: https://mmfit.github.io/ and https://github.com/KDMStromback/mm-fit
