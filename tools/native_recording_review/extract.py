"""Extract bounded, unmodified frames from verified native recording artifacts."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def extract(artifact: Path, output: Path) -> None:
    artifact = artifact.resolve(strict=True)
    output.mkdir(parents=True, exist_ok=False)
    receipts = []
    recordings = json.loads((artifact / "recordings.json").read_text())
    for recording in recordings:
        if recording.get("status") != "verified":
            receipts.append({"file": recording.get("file"), "skipped": "source recording is unverified"})
            continue
        source = (artifact / recording["file"]).resolve(strict=True)
        if not source.is_relative_to(artifact) or source.suffix != ".mp4":
            raise ValueError("recording is outside the input artifact or not an MP4")
        source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        if source_hash != recording["sha256"]:
            raise ValueError("recording does not match its captured device receipt")
        clock = json.loads(source.with_suffix(".frame-clock.json").read_text())
        video_pts = clock["videoPresentationSeconds"]
        device_pts = clock["deviceElapsedSeconds"]
        count = recording["frameCount"]
        if count < 2 or len(video_pts) != count or len(device_pts) != count:
            raise ValueError("native frame clock count differs from the recording receipt")
        # Short Back transitions retain every frame; longer clips retain five
        # indexed source frames. There is no interpolation or retiming.
        indices = list(range(count)) if count <= 16 else sorted({round((count - 1) * n / 4) for n in range(5)})
        destination = output / source.stem
        destination.mkdir()
        selection = "+".join(f"eq(n\\,{index})" for index in indices)
        result = subprocess.run([
            "ffmpeg", "-nostdin", "-v", "error", "-xerror", "-threads", "2", "-i", str(source),
            "-vf", "select=" + selection, "-fps_mode", "passthrough", "-threads", "1",
            str(destination / "frame-%02d.png"),
        ], capture_output=True, text=True, timeout=90)
        (destination / "decode.log").write_text(result.stderr, encoding="utf-8")
        if result.returncode or result.stderr.strip():
            raise ValueError("source failed strict decoding; extracted frames are not accepted")
        frames = sorted(destination.glob("frame-*.png"))
        if len(frames) != len(indices):
            raise ValueError("extracted frame count differs from the selected source indices")
        receipts.append({
            "source": recording["file"], "sourceSha256": source_hash,
            "visualReview": "pending", "transformation": "original decoded pixels; no scaling or interpolation",
            "frames": [{"file": str(frame.relative_to(output)), "sourceFrameIndex": index,
                        "videoPresentationSeconds": video_pts[index], "deviceElapsedSeconds": device_pts[index],
                        "sha256": hashlib.sha256(frame.read_bytes()).hexdigest()}
                       for frame, index in zip(frames, indices)],
        })
    (output / "review-frames.json").write_text(json.dumps(receipts, indent=2), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    extract(arguments.artifact, arguments.output)
