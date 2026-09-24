"""Inspect original purchase footage on hosted CI, without starting Android."""

import argparse
import bisect
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess

from tools.native_recording_review.together import picture_timing


def sample_indices(pts: list[float]) -> list[int]:
    """Retain the actual picture held at four-second intervals and both ends."""
    if len(pts) < 2 or any(not math.isfinite(x) for x in pts):
        raise ValueError('Require finite native frame timestamps')
    if any(b <= a for a, b in zip(pts, pts[1:])):
        raise ValueError('Native timestamps must be strictly increasing')
    if pts[-1] - pts[0] > 75:
        raise ValueError('Expected bounded purchase recording segments')
    indices = {0, len(pts) - 1}
    for second in range(4, math.ceil(pts[-1] - pts[0]), 4):
        indices.add(bisect.bisect_right(pts, pts[0] + second) - 1)
    return sorted(indices)


def review(artifact: Path, output: Path) -> None:
    artifact = artifact.resolve(strict=True)
    candidates = [p for p in artifact.rglob('run.json')
                  if isinstance(json.loads(p.read_text()), dict)
                  and 'recordingSegments' in json.loads(p.read_text())]
    if len(candidates) != 1:
        raise ValueError('Require exactly one purchase capture receipt')
    receipt_path = candidates[0]
    receipt = json.loads(receipt_path.read_text())
    if receipt.get('passed') is not True or receipt.get('driveExitCode') != 0:
        raise ValueError('Source purchase journey did not pass')
    segments = receipt['recordingSegments']
    if not 1 <= len(segments) <= 4:
        raise ValueError('Expected one to four purchase segments')
    output.mkdir(parents=True, exist_ok=False)
    records = []
    for segment in segments:
        name = segment['file']
        if re.fullmatch(r'journey-00[1-4]\.mp4', name) is None:
            raise ValueError('Unexpected native purchase segment name')
        source = (receipt_path.parent / name).resolve(strict=True)
        if not source.is_relative_to(artifact):
            raise ValueError('Source escapes its artifact')
        with source.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        probe = subprocess.run([
            'ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_frames',
            '-show_entries', 'frame=best_effort_timestamp_time:stream=time_base,width,height',
            '-of', 'json', str(source),
        ], capture_output=True, text=True, check=True, timeout=90)
        if probe.stderr.strip():
            raise ValueError('Native frame probe reported errors')
        decoded = json.loads(probe.stdout)
        pts, timing = picture_timing(decoded)
        indices = sample_indices(pts)
        stream = decoded['streams'][0]
        if [stream['width'], stream['height']] != segment['recordingPixels']:
            raise ValueError('Native capture dimensions disagree')
        time_base = stream['time_base']
        if re.fullmatch(r'[1-9]\d*/[1-9]\d*', time_base) is None:
            raise ValueError('Require a positive native time base')
        destination = output / source.stem
        destination.mkdir()
        selection = '+'.join(f'eq(n\\,{index})' for index in indices)
        result = subprocess.run([
            'ffmpeg', '-nostdin', '-v', 'error', '-xerror', '-threads', '2',
            '-i', str(source), '-vf', 'select=' + selection,
            '-fps_mode', 'passthrough', '-enc_time_base', time_base.replace('/', ':'),
            '-threads', '1', str(destination / 'frame-%02d.png'),
        ], capture_output=True, text=True, timeout=120)
        (destination / 'decode.log').write_text(result.stderr, encoding='utf-8')
        frames = sorted(destination.glob('frame-*.png'))
        if result.returncode or result.stderr.strip() or len(frames) != len(indices):
            raise ValueError('Strict native frame extraction failed')
        records.append({
            'source': name, 'sourceSha256': digest, 'sourceTimeBase': time_base,
            'sourcePixels': segment['recordingPixels'], 'timing': timing,
            'captureReceipt': segment, 'decodeExitCode': result.returncode,
            'visualReview': 'pending',
            'transformation': 'Original decoded pixels; no scaling, retiming or interpolation.',
            'boundary': 'RevenueCat Test Store; Android emulator; native player plus headless TLS peer.',
            'frames': [{'file': str(frame.relative_to(output)), 'sourceFrameIndex': n,
                        'videoPresentationSeconds': pts[n],
                        'sha256': hashlib.sha256(frame.read_bytes()).hexdigest()}
                       for frame, n in zip(frames, indices)],
        })
    (output / 'review-frames.json').write_text(json.dumps(records, indent=2), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    review(args.artifact, args.output)
