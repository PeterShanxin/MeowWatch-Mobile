"""Audit original Together picture timing and extract bounded review PNGs."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess


def picture_timing(probe: dict) -> tuple[list[float], dict]:
    frames = probe['frames']
    pts = [float(frame['best_effort_timestamp_time']) for frame in frames]
    if len(pts) < 2 or not all(math.isfinite(value) for value in pts):
        raise ValueError('Need at least two finite native picture timestamps')
    gaps = [b - a for a, b in zip(pts, pts[1:])]
    if min(gaps) <= 0:
        raise ValueError('Native picture timestamps must be strictly increasing')
    longest = sorted(range(len(gaps)), key=gaps.__getitem__, reverse=True)[:5]
    return pts, {
        'pictureCount': len(pts), 'firstPtsSeconds': pts[0], 'lastPtsSeconds': pts[-1],
        'meanPicturesPerSecond': (len(pts) - 1) / (pts[-1] - pts[0]),
        'maxPictureGapSeconds': max(gaps),
        'gapsOverHalfSecond': sum(value > .5 for value in gaps),
        'longestGaps': [{'afterFrameIndex': index, 'startSeconds': pts[index],
                         'endSeconds': pts[index + 1], 'seconds': gaps[index]}
                        for index in longest],
    }


def review(artifact: Path, output: Path) -> None:
    artifact = artifact.resolve(strict=True)
    manifests = list(artifact.rglob('meowwatch-two-device.mp4.manifest.json'))
    if len(manifests) != 1:
        raise ValueError('Require exactly one Together session manifest')
    manifest_path = manifests[0]
    manifest = json.loads(manifest_path.read_text())
    output.mkdir(parents=True, exist_ok=False)
    receipts = []
    for role, serial in [('phone', 'emulator-5554'), ('tablet', 'emulator-5556')]:
        segments = manifest['sources'][role]['segments']
        if not 1 <= len(segments) <= 8:
            raise ValueError('Expected one to eight recorded segments per role')
        for index, segment in enumerate(segments):
            name = f'{role}-{index:03d}.mp4'
            if Path(segment['path']).name != name or segment['status'] != 'available':
                raise ValueError('All manifest segments must be named available originals')
            source = (manifest_path.parent / f'{role}-{serial}' / 'segments' / name).resolve(strict=True)
            if not source.is_relative_to(artifact):
                raise ValueError('Original segment is outside the artifact')
            with source.open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            if digest != segment['sha256']:
                raise ValueError('Original segment hash differs from manifest')
            probe = subprocess.run([
                'ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_frames',
                '-show_entries', 'frame=best_effort_timestamp_time:stream=time_base',
                '-of', 'json', str(source),
            ], capture_output=True, text=True, check=True, timeout=90)
            if probe.stderr.strip():
                raise ValueError('Native frame probe reported errors')
            decoded = json.loads(probe.stdout)
            pts, timing = picture_timing(decoded)
            if len(pts) != int(segment['probe']['streams'][0]['nb_frames']):
                raise ValueError('Picture count differs from captured manifest')
            time_base = decoded['streams'][0]['time_base']
            if re.fullmatch(r'[1-9]\d*/[1-9]\d*', time_base) is None:
                raise ValueError('Require a positive native source time base')
            indices = {round((len(pts) - 1) * n / 6) for n in range(7)}
            # Include the pictures immediately around the longest actual gap.
            gap_index = timing['longestGaps'][0]['afterFrameIndex']
            indices.update((gap_index, gap_index + 1))
            indices = sorted(indices)
            destination = output / source.stem
            destination.mkdir()
            selection = '+'.join(f'eq(n\\,{value})' for value in indices)
            result = subprocess.run([
                'ffmpeg', '-nostdin', '-v', 'error', '-xerror', '-threads', '2',
                '-i', str(source), '-vf', 'select=' + selection,
                '-fps_mode', 'passthrough', '-enc_time_base', time_base.replace('/', ':'),
                '-threads', '1', str(destination / 'frame-%02d.png'),
            ], capture_output=True, text=True, timeout=120)
            (destination / 'decode.log').write_text(result.stderr, encoding='utf-8')
            if result.returncode or result.stderr.strip():
                raise ValueError('Strict original decode failed')
            frames = sorted(destination.glob('frame-*.png'))
            if len(frames) != len(indices):
                raise ValueError('Extracted frame count differs from selected indices')
            (destination / 'picture-pts.json').write_text(json.dumps(pts), encoding='utf-8')
            receipts.append({
                'role': role, 'source': name, 'sourceSha256': digest,
                'sourceTimeBase': time_base, 'decodeExitCode': result.returncode,
                'timing': timing, 'visualReview': 'pending',
                'boundary': 'Original per-device PTS; not inter-device frame alignment or physical hardware.',
                'transformation': 'Original decoded pixels; no scaling, interpolation or retiming.',
                'frames': [{'file': str(frame.relative_to(output)), 'sourceFrameIndex': n,
                            'videoPresentationSeconds': pts[n],
                            'sha256': hashlib.sha256(frame.read_bytes()).hexdigest()}
                           for frame, n in zip(frames, indices)],
            })
    (output / 'review-frames.json').write_text(json.dumps(receipts, indent=2), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    review(args.artifact, args.output)
