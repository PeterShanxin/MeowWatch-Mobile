#!/usr/bin/env python3
"""Compose timestamp-aligned native Android recordings for human review."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Mapping, Sequence


FRAME_RATE = 30
CANVAS = (1920, 1080)
DEVELOPMENT_LABEL = "Development test / synchronization verification in progress"


@dataclass(frozen=True)
class Alignment:
    phone_start_ns: int
    tablet_start_ns: int
    phone_delay_seconds: Decimal
    tablet_delay_seconds: Decimal


def read_tsv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not raw_line:
            continue
        columns = raw_line.split("\t")
        if len(columns) != 2 or not columns[0]:
            raise ValueError(f"Malformed timing row {line_number}: {raw_line!r}")
        values[columns[0]] = columns[1]
    return values


def compute_alignment(values: Mapping[str, str]) -> Alignment:
    try:
        phone_start = int(values["phone_first_segment_ns"])
        tablet_start = int(values["tablet_first_segment_ns"])
    except (KeyError, ValueError) as error:
        raise ValueError(
            "Timing evidence must contain integer phone/tablet first-segment timestamps."
        ) from error
    if phone_start < 0 or tablet_start < 0:
        raise ValueError("Recorder start timestamps cannot be negative.")
    origin = min(phone_start, tablet_start)
    billion = Decimal(1_000_000_000)
    return Alignment(
        phone_start_ns=phone_start,
        tablet_start_ns=tablet_start,
        phone_delay_seconds=Decimal(phone_start - origin) / billion,
        tablet_delay_seconds=Decimal(tablet_start - origin) / billion,
    )


def _seconds(value: Decimal) -> str:
    return f"{value:.6f}"


def _escape_filter_text(value: str) -> str:
    return (
        value.replace("\\", r"\\")
        .replace("'", r"\'")
        .replace(":", r"\:")
        .replace("%", r"\%")
    )


def _escape_filter_path(path: Path) -> str:
    return path.resolve().as_posix().replace(":", r"\:").replace("'", r"\'")


def find_font(explicit: Path | None = None) -> Path:
    candidates: list[Path] = []
    if explicit is not None:
        candidates.append(explicit)
    if os.environ.get("FONT_FILE"):
        candidates.append(Path(os.environ["FONT_FILE"]))
    if os.environ.get("WINDIR"):
        fonts = Path(os.environ["WINDIR"]) / "Fonts"
        candidates.extend([fonts / "segoeui.ttf", fonts / "arial.ttf"])
    candidates.extend(
        [
            Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
            Path("/Library/Fonts/Arial.ttf"),
            Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
        ]
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise FileNotFoundError(
        "No presentation font found. Set FONT_FILE or pass --font-file."
    )


def probe_video(ffprobe: str, path: Path) -> dict[str, object]:
    result = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=codec_name,width,height,r_frame_rate,avg_frame_rate,duration",
            "-show_entries",
            "format=duration,start_time",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def video_duration(probe: Mapping[str, object]) -> Decimal:
    streams = probe.get("streams")
    if not isinstance(streams, list) or not streams:
        raise ValueError("Recording has no video stream.")
    stream = streams[0]
    if not isinstance(stream, dict):
        raise ValueError("Recording video metadata is malformed.")
    raw = stream.get("duration")
    if raw is None:
        format_data = probe.get("format")
        raw = format_data.get("duration") if isinstance(format_data, dict) else None
    if raw is None:
        raise ValueError("Recording duration is unavailable.")
    duration = Decimal(str(raw))
    if duration <= 0:
        raise ValueError("Recording duration must be positive.")
    return duration


def video_dimensions(probe: Mapping[str, object]) -> tuple[int, int]:
    streams = probe.get("streams")
    if not isinstance(streams, list) or not streams or not isinstance(streams[0], dict):
        raise ValueError("Recording has no video stream.")
    try:
        width = int(streams[0]["width"])
        height = int(streams[0]["height"])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("Recording dimensions are unavailable.") from error
    if width <= 0 or height <= 0:
        raise ValueError("Recording dimensions must be positive.")
    return width, height


def build_filter_graph(
    *,
    alignment: Alignment,
    duration: Decimal,
    font_file: Path,
    phone_label: str,
    tablet_label: str,
    result_label: str | None,
    tablet_is_landscape: bool = False,
) -> str:
    font = _escape_filter_path(font_file)
    phone_text = _escape_filter_text(phone_label)
    tablet_text = _escape_filter_text(tablet_label)
    development_text = _escape_filter_text(DEVELOPMENT_LABEL)
    result_text = _escape_filter_text(result_label) if result_label else ""
    duration_text = _seconds(duration)
    phone_delay = _seconds(alignment.phone_delay_seconds)
    tablet_delay = _seconds(alignment.tablet_delay_seconds)

    text_options = f"fontfile='{font}':fontcolor=0xF5EDE0"
    if tablet_is_landscape:
        phone_x, phone_y = 250, 150
        tablet_x, tablet_y = 710, 238
        tablet_scale = "scale=920:600:force_original_aspect_ratio=decrease"
        tablet_inner_pad = "pad=920:600:(ow-iw)/2:(oh-ih)/2:color=0x05070B"
        tablet_outer_pad = "pad=960:648:20:24:color=0x29303D"
        tablet_label_y = 200
        tablet_outer_width = 960
    else:
        phone_x, phone_y = 430, 150
        tablet_x, tablet_y = 950, 150
        tablet_scale = "scale=500:776:force_original_aspect_ratio=decrease"
        tablet_inner_pad = "pad=500:776:(ow-iw)/2:(oh-ih)/2:color=0x05070B"
        tablet_outer_pad = "pad=540:824:20:24:color=0x29303D"
        tablet_label_y = 112
        tablet_outer_width = 540

    graph = [
        f"color=c=0x0D111A:s={CANVAS[0]}x{CANVAS[1]}:r={FRAME_RATE}:d={duration_text}[background]",
        (
            "[0:v:0]fps=30,setpts=PTS-STARTPTS,"
            f"tpad=start_mode=add:color=0x05070B:start_duration={phone_delay},"
            "scale=350:776:force_original_aspect_ratio=decrease,"
            "pad=350:776:(ow-iw)/2:(oh-ih)/2:color=0x05070B,setsar=1,"
            "pad=390:824:20:24:color=0x29303D,"
            "drawbox=x=0:y=0:w=iw:h=ih:color=0x687184:t=2,"
            "drawbox=x=(w-72)/2:y=10:w=72:h=4:color=0x8992A3:t=fill[phone]"
        ),
        (
            "[1:v:0]fps=30,setpts=PTS-STARTPTS,"
            f"tpad=start_mode=add:color=0x05070B:start_duration={tablet_delay},"
            f"{tablet_scale},{tablet_inner_pad},setsar=1,{tablet_outer_pad},"
            "drawbox=x=0:y=0:w=iw:h=ih:color=0x687184:t=2,"
            "drawbox=x=(w-72)/2:y=10:w=72:h=4:color=0x8992A3:t=fill[tablet]"
        ),
        f"[background][phone]overlay=x={phone_x}:y={phone_y}:shortest=1[with_phone]",
        f"[with_phone][tablet]overlay=x={tablet_x}:y={tablet_y}:shortest=1[devices]",
        (
            f"[devices]drawtext={text_options}:text='MEOWWATCH  /  MULTI-DEVICE CAPTURE':"
            "fontsize=36:x=72:y=36,"
            f"drawtext={text_options}:fontcolor=0xB5BDCC:text='{phone_text}':"
            f"fontsize=24:x={phone_x}+(390-text_w)/2:y=112,"
            f"drawtext={text_options}:fontcolor=0xB5BDCC:text='{tablet_text}':"
            f"fontsize=24:x={tablet_x}+({tablet_outer_width}-text_w)/2:y={tablet_label_y},"
            f"drawtext={text_options}:fontcolor=0xEFB38C:text='{development_text}':"
            "fontsize=25:x=(w-text_w)/2:y=1017"
            + (
                f",drawtext={text_options}:fontcolor=0xEFB38C:text='{result_text}':"
                "fontsize=24:x=w-text_w-72:y=42"
                if result_label
                else ""
            )
            + "[out]"
        ),
    ]
    return ";".join(graph)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Compose aligned phone/tablet Android recordings."
    )
    result.add_argument("phone_video", type=Path)
    result.add_argument("tablet_video", type=Path)
    result.add_argument("timing_file", type=Path)
    result.add_argument("output_video", type=Path)
    result.add_argument("--result-label")
    result.add_argument("--font-file", type=Path)
    result.add_argument("--ffmpeg", default="ffmpeg")
    result.add_argument("--ffprobe", default="ffprobe")
    result.add_argument("--preset", default="medium")
    result.add_argument("--crf", type=int, default=18)
    return result


def _binary(value: str) -> str:
    found = shutil.which(value)
    if found is None:
        raise FileNotFoundError(f"Required executable is unavailable: {value}")
    return found


def main(argv: Sequence[str] | None = None) -> int:
    args = parser().parse_args(argv)
    for source in (args.phone_video, args.tablet_video, args.timing_file):
        if not source.is_file():
            raise FileNotFoundError(f"Input evidence is missing: {source}")
    ffmpeg = _binary(args.ffmpeg)
    ffprobe = _binary(args.ffprobe)
    font = find_font(args.font_file)
    timing = read_tsv(args.timing_file)
    alignment = compute_alignment(timing)
    phone_probe = probe_video(ffprobe, args.phone_video)
    tablet_probe = probe_video(ffprobe, args.tablet_video)
    phone_duration = video_duration(phone_probe)
    tablet_duration = video_duration(tablet_probe)
    tablet_width, tablet_height = video_dimensions(tablet_probe)
    common_duration = min(
        alignment.phone_delay_seconds + phone_duration,
        alignment.tablet_delay_seconds + tablet_duration,
    )
    phone_label = f"PHONE / {timing.get('phone_serial', 'unknown source')} / native recording"
    tablet_label = (
        f"TABLET / {timing.get('tablet_serial', 'unknown source')} / native recording"
    )
    filter_graph = build_filter_graph(
        alignment=alignment,
        duration=common_duration,
        font_file=font,
        phone_label=phone_label,
        tablet_label=tablet_label,
        result_label=args.result_label,
        tablet_is_landscape=tablet_width > tablet_height,
    )

    args.output_video.parent.mkdir(parents=True, exist_ok=True)
    command = [
        ffmpeg,
        "-hide_banner",
        "-y",
        "-i",
        str(args.phone_video),
        "-i",
        str(args.tablet_video),
        "-filter_complex",
        filter_graph,
        "-map",
        "[out]",
        "-an",
        "-r",
        str(FRAME_RATE),
        "-t",
        _seconds(common_duration),
        "-c:v",
        "libx264",
        "-preset",
        args.preset,
        "-crf",
        str(args.crf),
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        str(args.output_video),
    ]
    subprocess.run(command, check=True)

    output_probe = probe_video(ffprobe, args.output_video)
    output_hash = sha256(args.output_video)
    manifest = {
        "schemaVersion": 1,
        "presentation": {
            "width": CANVAS[0],
            "height": CANVAS[1],
            "frameRate": FRAME_RATE,
            "developmentLabel": DEVELOPMENT_LABEL,
            "resultLabel": args.result_label,
            "tabletLayout": "landscape" if tablet_width > tablet_height else "portrait",
        },
        "alignment": {
            "phoneFirstSegmentNs": alignment.phone_start_ns,
            "tabletFirstSegmentNs": alignment.tablet_start_ns,
            "phoneDelaySeconds": _seconds(alignment.phone_delay_seconds),
            "tabletDelaySeconds": _seconds(alignment.tablet_delay_seconds),
            "commonDurationSeconds": _seconds(common_duration),
        },
        "sources": {
            "phone": {
                "path": str(args.phone_video.resolve()),
                "sha256": sha256(args.phone_video),
                "probe": phone_probe,
            },
            "tablet": {
                "path": str(args.tablet_video.resolve()),
                "sha256": sha256(args.tablet_video),
                "probe": tablet_probe,
            },
            "timing": {
                "path": str(args.timing_file.resolve()),
                "sha256": sha256(args.timing_file),
            },
        },
        "output": {
            "path": str(args.output_video.resolve()),
            "sha256": output_hash,
            "probe": output_probe,
        },
    }
    args.output_video.with_suffix(args.output_video.suffix + ".manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    args.output_video.with_suffix(args.output_video.suffix + ".sha256").write_text(
        f"{output_hash}  {args.output_video.name}\n", encoding="utf-8"
    )
    args.output_video.with_suffix(args.output_video.suffix + ".ffprobe.json").write_text(
        json.dumps(output_probe, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Framed multi-device recording: {args.output_video}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, ValueError, subprocess.CalledProcessError) as error:
        print(f"compose_side_by_side: {error}", file=sys.stderr)
        raise SystemExit(2) from error
