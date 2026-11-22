"""Inspect MM-Fit native assets, or convert *verified* 2D keypoint arrays.

Do not guess the native MM-Fit pose layout or keypoint ordering. Call inspect
first, then supply an explicit joint index mapping for this dataset copy.
NumPy is required only for the .npy adapter; the replay evaluator uses stdlib.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

JOINTS = ('shoulder', 'elbow', 'wrist', 'hip', 'knee', 'ankle')
NAMES = tuple(f'{side}_{joint}' for side in ('left', 'right') for joint in JOINTS)


def _np():
    try:
        import numpy as np
        return np
    except ImportError as exc:
        raise RuntimeError('pip install numpy (see requirements-mmfit.txt)') from exc


def inspect(root: Path) -> None:
    np = _np()
    pose_files = sorted(root.rglob('w*_pose_2d.npy'))
    labels = sorted(root.rglob('w*_labels.csv'))
    print('Found pose arrays:', len(pose_files), 'label CSV files:', len(labels))
    for p in pose_files[:30]:
        arr = np.load(p, mmap_mode='r', allow_pickle=False)
        print('POSE', p, 'shape', arr.shape, 'dtype', arr.dtype)
    for p in labels[:30]:
        with p.open(encoding='utf-8-sig', newline='') as file:
            reader = csv.reader(file)
            rows = [next(reader, []) for _ in range(2)]
        print('LABEL', p, 'first two rows', rows)
    if not pose_files:
        print('No expected wXX_pose_2d.npy files. Check MM-Fit root; nothing converted.')


def convert(input_path: Path, output_path: Path, mapping_path: Path,
            fps: float, width: float, height: float, coordinate_type: str,
            layout: str, timestamp_start: float) -> int:
    np = _np()
    if fps <= 0 or width <= 0 or height <= 0:
        raise ValueError('fps and video dimensions must be positive')
    mapping = json.loads(mapping_path.read_text(encoding='utf-8'))
    indices = mapping.get('joint_indices', {})
    if set(indices) != set(NAMES) or any(not isinstance(v, int) or v < 0 for v in indices.values()):
        raise ValueError('Mapping must explicitly give integer index for all 12 joints')
    confidence_index = mapping.get('confidence_coordinate_index')
    if confidence_index is not None and (not isinstance(confidence_index, int) or confidence_index < 0):
        raise ValueError('confidence_coordinate_index must be null or a nonnegative integer')
    arr = np.load(input_path, mmap_mode='r', allow_pickle=False)
    if arr.ndim != 3:
        raise ValueError(f'Expected 3D pose array, got shape={arr.shape}')
    if layout == 'frames-coordinates-joints':
        arr = arr.transpose(0,2,1)
    if max(indices.values()) >= arr.shape[1]:
        raise ValueError(f'Mapping joint index outside input shape {arr.shape}')
    if arr.shape[2] < 2 or (confidence_index is not None and confidence_index >= arr.shape[2]):
        raise ValueError(f'Coordinates missing in shape {arr.shape}')
    if confidence_index is None:
        print('NOTE: No real confidence field present. Imputing 0.95 for present points; '
              'NOT a detector confidence measurement.')
    output_path.parent.mkdir(parents=True, exist_ok=True)
    valid = 0
    common_scale = max(width, height)
    with output_path.open('w', encoding='utf-8') as out:
        for n, frame in enumerate(arr):
            points = {}
            for name, index in indices.items():
                data = frame[index]
                x = float(data[0]); y = float(data[1])
                if coordinate_type == 'normalized-image':
                    x *= width
                    y *= height
                x /= common_scale
                y /= common_scale
                confidence = float(data[confidence_index]) if confidence_index is not None else 0.95
                if (math.isfinite(x) and math.isfinite(y) and
                        math.isfinite(confidence) and 0 <= x <= 1 and 0 <= y <= 1 and
                        0 <= confidence <= 1):
                    points[name] = {'x': x, 'y': y, 'confidence': confidence}
            if points:
                valid += 1
            event = {'timestamp_ms': round(timestamp_start + 1000 * n / fps),
                     'landmarks': points}
            out.write(json.dumps(event, separators=(',', ':')) + '\n')
    print(f'Converted {len(arr)} frames ({valid} with points) to {output_path}; '
          'ground truth labels NOT inferred')
    return len(arr)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest='command', required=True)
    a = sub.add_parser('inspect')
    a.add_argument('--root', type=Path, required=True)
    a = sub.add_parser('convert')
    a.add_argument('--input', type=Path, required=True)
    a.add_argument('--output', type=Path, required=True)
    a.add_argument('--mapping', type=Path, required=True)
    a.add_argument('--fps', type=float, required=True)
    a.add_argument('--width', type=float, required=True)
    a.add_argument('--height', type=float, required=True)
    a.add_argument('--coordinate-type', choices=['pixels', 'normalized-image'], required=True)
    a.add_argument('--layout', choices=['frames-joints-coordinates', 'frames-coordinates-joints'],
                   required=True)
    a.add_argument('--timestamp-start-ms', type=float, default=0.)
    args = ap.parse_args()
    try:
        if args.command == 'inspect':
            inspect(args.root)
        else:
            convert(args.input, args.output, args.mapping, args.fps, args.width,
                    args.height, args.coordinate_type, args.layout, args.timestamp_start_ms)
    except (RuntimeError, ValueError, OSError) as exc:
        ap.exit(2, f'MM-Fit adapter failed: {exc}\n')


if __name__ == '__main__':
    main()
