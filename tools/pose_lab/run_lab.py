"""Evaluate production-Dart rep counting against labeled sessions.

No data leaves the machine. The script does NOT treat MM-Fit native keypoints as
MediaPipe keypoints. Convert with a verified mapping first.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
from pathlib import Path

REQUIRED = ("session_id", "exercise", "pose_jsonl", "ground_truth_reps")


def read_manifest(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames or any(k not in reader.fieldnames for k in REQUIRED):
            raise ValueError(f"Manifest must contain {', '.join(REQUIRED)}")
        sessions = list(reader)
    if not sessions:
        raise ValueError("Manifest is empty")
    seen = set()
    for row in sessions:
        sid = row["session_id"]
        if not sid or re.fullmatch(r'[A-Za-z0-9_-]+', sid) is None:
            raise ValueError(f"Unsafe or missing session_id: {sid!r}")
        if sid in seen:
            raise ValueError(f"Duplicate session_id: {sid}")
        seen.add(sid)
        if row["exercise"].lower() not in ("squat", "pushup"):
            raise ValueError(f"Unsupported exercise: {row['exercise']}")
        if not row["ground_truth_reps"].isdigit():
            raise ValueError(f"Invalid ground truth count: {sid}")
    return sessions


def match_events(predicted: list[int], truth: list[int], tolerance_ms: int) -> tuple[int,int,int]:
    """One-to-one chronological matching, only for annotated individual reps."""
    matched = set()
    tp = 0
    for pred in predicted:
        candidates = [i for i, t in enumerate(truth)
                      if i not in matched and abs(pred - t) <= tolerance_ms]
        if candidates:
            chosen = min(candidates, key=lambda i: abs(pred - truth[i]))
            matched.add(chosen)
            tp += 1
    return tp, len(predicted) - tp, len(truth) - tp


def evaluate(sessions: list[dict], manifest: Path, results: Path, tolerance_ms: int) -> list[dict]:
    output = []
    for row in sessions:
        pred_path = results / (row["session_id"] + '.json')
        if not pred_path.is_file():
            raise FileNotFoundError(f"Replay result missing: {pred_path}")
        prediction = json.loads(pred_path.read_text(encoding='utf-8'))
        n = int(prediction['predicted_reps'])
        true = int(row['ground_truth_reps'])
        times = prediction.get('rep_timestamps_ms', [])
        if n != len(times):
            raise ValueError(f"Prediction count / timestamps mismatch: {row['session_id']}")
        actual_path = row.get('truth_events_json', '').strip()
        precision = recall = f1 = ''
        tp = fp = fn = ''
        if actual_path:
            gt = json.loads((manifest.parent / actual_path).read_text(encoding='utf-8'))
            if len(gt) != true or not all(isinstance(x, int) for x in gt):
                raise ValueError(f"Ground truth event count mismatch: {row['session_id']}")
            tp, fp, fn = match_events(times, gt, tolerance_ms)
            precision = round(tp / (tp + fp), 4) if tp + fp else (1.0 if not gt else 0.0)
            recall = round(tp / (tp + fn), 4) if tp + fn else 1.0
            f1 = round(2 * precision * recall / (precision + recall), 4) if precision + recall else 0.0
        output.append({
            'session_id': row['session_id'], 'exercise': row['exercise'],
            'subject': row.get('subject', ''), 'view': row.get('view', ''),
            'cadence': row.get('cadence', ''), 'source': row.get('source', ''),
            'ground_truth_reps': true, 'predicted_reps': n,
            'absolute_error': abs(n - true), 'signed_error': n - true,
            'frames': prediction.get('frames', ''),
            'frames_without_landmarks': prediction.get('frames_without_landmarks', ''),
            'tp': tp, 'fp': fp, 'fn': fn,
            'precision': precision, 'recall': recall, 'f1': f1,
        })
    return output



# Resolve the Dart executable before starting replay. On Windows, Flutter can
# be available through a PowerShell shim even when `dart` is not in PATH for
# Python subprocesses. Do not change pose data or inference behavior here.
def resolve_dart_executable(explicit: str | None, mobile_dir: Path) -> str:
    import os
    import shutil

    if explicit:
        path = Path(explicit).expanduser()
        if path.is_file():
            return str(path.resolve())
        found = shutil.which(explicit)
        if found:
            return found
        raise FileNotFoundError(
            f'Dart executable not found at --dart={explicit!r}. '
            'Use the full path to flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe.'
        )

    found = shutil.which('dart')
    if found:
        return found

    bin_dirs: list[Path] = []
    flutter = shutil.which('flutter')
    if flutter:
        bin_dirs.append(Path(flutter).resolve().parent)
    flutter_root = os.environ.get('FLUTTER_ROOT')
    if flutter_root:
        bin_dirs.append(Path(flutter_root).expanduser().resolve() / 'bin')
    # FVM project-local SDK is a common Flutter project setup.
    repo_root = mobile_dir.resolve().parents[1]
    bin_dirs.append(repo_root / '.fvm' / 'flutter_sdk' / 'bin')
    for base in bin_dirs:
        for executable in ('dart.exe', 'dart'):
            candidate = base / 'cache' / 'dart-sdk' / 'bin' / executable
            if candidate.is_file():
                return str(candidate)
    raise FileNotFoundError(
        'Dart executable is not visible to Python. From PowerShell run '
        '`Get-Command flutter` to locate flutter\\bin, then pass '
        '`--dart "C:\\\\path\\\\to\\\\flutter\\\\bin\\\\cache\\\\dart-sdk\\\\bin\\\\dart.exe"`. '
        'Or add the Flutter SDK bin directory to PATH.'
    )

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--manifest', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True, help='Output folder')
    ap.add_argument('--mobile-dir', type=Path, help='apps/mobile folder for Dart replay')
    ap.add_argument('--dart', default=None, help='Optional full path to dart.exe (auto-detected if absent)')
    ap.add_argument('--skip-replay', action='store_true', help='Use previously generated JSON predictions')
    ap.add_argument('--tolerance-ms', type=int, default=550)
    args = ap.parse_args(argv)
    if args.tolerance_ms < 0:
        ap.error('tolerance must be nonnegative')
    sessions = read_manifest(args.manifest)
    args.out.mkdir(parents=True, exist_ok=True)
    result_dir = args.out / 'predictions'
    result_dir.mkdir(exist_ok=True)
    if not args.skip_replay:
        if not args.mobile_dir:
            ap.error('--mobile-dir is required unless --skip-replay')
        runner = args.mobile_dir / 'tool/pose_lab/replay.dart'
        if not runner.exists():
            ap.error(f'Expected Dart runner: {runner}')
        dart_command = resolve_dart_executable(args.dart, args.mobile_dir)
        for session in sessions:
            pose = (args.manifest.parent / session['pose_jsonl']).resolve()
            if not pose.is_file():
                raise FileNotFoundError(f"Missing input: {pose}")
            command = [dart_command, 'run', 'tool/pose_lab/replay.dart', '--input', str(pose),
                       '--exercise', session['exercise'],
                       '--output', str((result_dir / (session['session_id']+'.json')).resolve())]
            print('Replay:', session['session_id'], flush=True)
            subprocess.run(command, cwd=args.mobile_dir, check=True)
    output = evaluate(sessions, args.manifest, result_dir, args.tolerance_ms)
    with (args.out/'session_results.csv').open('w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=list(output[0]))
        w.writeheader()
        w.writerows(output)
    mae = sum(x['absolute_error'] for x in output) / len(output)
    summary = {
        'sessions': len(output), 'count_mae': round(mae, 4),
        'total_true_reps': sum(x['ground_truth_reps'] for x in output),
        'total_predicted_reps': sum(x['predicted_reps'] for x in output),
        'sessions_with_per_rep_annotations': sum(bool(x['precision'] != '') for x in output),
        'note': 'Per-rep precision/recall require manually verified event timestamps. '
                'Count MAE alone cannot establish rep precision or recall. '
                'Synthetic fixtures do not measure real-world accuracy.',
    }
    (args.out/'summary.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f'LAB failed: {exc}', file=sys.stderr)
        raise SystemExit(2)
