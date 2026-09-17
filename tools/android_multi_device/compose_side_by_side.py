#!/usr/bin/env python3
"""Compose raw Android segments on an estimated host-command timeline."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path

FRAME_RATE = 30
CANVAS = (1920, 1080)
DEVELOPMENT_LABEL = "Development test / synchronization verification in progress"
TIMING_LABEL = (
    "Host ADB command timing / approximate alignment, not frame synchronization"
)


@dataclass(frozen=True)
class Segment:
    index: int
    start_ns: int
    path: Path
    probe: dict[str, object] | None

    @property
    def duration(self) -> Decimal:
        return video_duration(self.probe) if self.probe is not None else Decimal(0)


def read_segments(
    role: str, video: Path, timing_file: Path, ffprobe: str
) -> list[Segment]:
    metadata = timing_file.parent / "recorder-control" / f"{role}-segments.tsv"
    segments = []
    for row in metadata.read_text(encoding="utf-8").splitlines():
        fields = row.split("\t")
        if len(fields) != 3:
            raise ValueError(f"Malformed {role} segment timing row: {row!r}")
        index, start = int(fields[0]), int(fields[1])
        name = fields[2]
        if (
            index != len(segments)
            or start < 0
            or name != f"{role}-{index:03d}.mp4"
            or (segments and start <= segments[-1].start_ns)
        ):
            raise ValueError(f"Invalid or missing {role} segment timing row: {row!r}")
        path = video.parent / "segments" / name
        probe = probe_video(ffprobe, path) if path.is_file() else None
        segments.append(Segment(index, start, path, probe))
    if not segments:
        raise ValueError(f"No {role} segment timing evidence")
    listed = {segment.path.name for segment in segments}
    actual = {path.name for path in (video.parent / "segments").glob("*.mp4")}
    if actual - listed:
        raise ValueError(
            f"Native {role} segments lack timing rows: {sorted(actual - listed)}"
        )
    return segments


def segment_intervals(
    segments: Sequence[Segment], origin_ns: int
) -> list[tuple[Decimal, Decimal]]:
    intervals = []
    for index, segment in enumerate(segments):
        start = Decimal(segment.start_ns - origin_ns) / Decimal(1_000_000_000)
        end = start + segment.duration
        if index + 1 < len(segments):
            following = Decimal(segments[index + 1].start_ns - origin_ns) / Decimal(
                1_000_000_000
            )
            end = min(end, following)
        intervals.append((start, end))
    return intervals


def recording_gaps(
    intervals: Sequence[tuple[Decimal, Decimal]], duration: Decimal
) -> list[tuple[Decimal, Decimal]]:
    gaps = []
    cursor = Decimal(0)
    for start, end in intervals:
        if end <= start:
            continue
        if start > cursor:
            gaps.append((cursor, start))
        cursor = max(cursor, end)
    if cursor < duration:
        gaps.append((cursor, duration))
    return gaps


def build_timeline_graph(
    role: str,
    segments: Sequence[Segment],
    origin_ns: int,
    duration: Decimal,
    font_file: Path,
    input_index: int,
    width: int,
    height: int,
) -> tuple[list[str], list[Path]]:
    font = _escape_filter_path(font_file)
    filters = [
        f"color=c=0x05070B:s={width}x{height}:r={FRAME_RATE}:d={_seconds(duration)},"
        f"drawtext=fontfile='{font}':fontcolor=0xEFB38C:text='RECORDING GAP':"
        "fontsize=22:x=(w-text_w)/2:y=h/2-26,"
        f"drawtext=fontfile='{font}':fontcolor=0xB5BDCC:text='No captured frames':"
        f"fontsize=17:x=(w-text_w)/2:y=h/2+8[{role}_base]"
    ]
    previous = f"{role}_base"
    sources = []
    for segment, (start, end) in zip(segments, segment_intervals(segments, origin_ns)):
        if segment.probe is None:
            continue
        label = f"{role}_segment_{segment.index}"
        output = f"{role}_overlay_{segment.index}"
        filters.append(
            f"[{input_index + len(sources)}:v:0]setpts=PTS-STARTPTS,"
            f"scale={width}:{height}:force_original_aspect_ratio=decrease,"
            f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=0x05070B,"
            f"setsar=1,fps={FRAME_RATE},setpts=PTS+{_seconds(start)}/TB[{label}]"
        )
        filters.append(
            f"[{previous}][{label}]overlay=eof_action=pass:repeatlast=0:"
            f"enable='gte(t,{_seconds(start)})*lt(t,{_seconds(end)})'[{output}]"
        )
        sources.append(segment.path)
        previous = output
    filters.append(f"[{previous}]null[{role}_timeline]")
    return filters, sources


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
    phone_input: str = "0:v:0",
    tablet_input: str = "1:v:0",
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
            f"[{phone_input}]fps=30,setpts=PTS-STARTPTS,"
            f"tpad=start_mode=add:color=0x05070B:start_duration={phone_delay},"
            "scale=350:776:force_original_aspect_ratio=decrease,"
            "pad=350:776:(ow-iw)/2:(oh-ih)/2:color=0x05070B,setsar=1,"
            "pad=390:824:20:24:color=0x29303D,"
            "drawbox=x=0:y=0:w=iw:h=ih:color=0x687184:t=2,"
            "drawbox=x=(w-72)/2:y=10:w=72:h=4:color=0x8992A3:t=fill[phone]"
        ),
        (
            f"[{tablet_input}]fps=30,setpts=PTS-STARTPTS,"
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
            "fontsize=25:x=(w-text_w)/2:y=997,"
            f"drawtext={text_options}:fontcolor=0xB5BDCC:text='{_escape_filter_text(TIMING_LABEL)}':"
            "fontsize=20:x=(w-text_w)/2:y=1038"
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
    for source in (args.timing_file,):
        if not source.is_file():
            raise FileNotFoundError(f"Input evidence is missing: {source}")
    ffmpeg = _binary(args.ffmpeg)
    ffprobe = _binary(args.ffprobe)
    font = find_font(args.font_file)
    timing = read_tsv(args.timing_file)
    alignment = compute_alignment(timing)
    phone_segments = read_segments("phone", args.phone_video, args.timing_file, ffprobe)
    tablet_segments = read_segments(
        "tablet", args.tablet_video, args.timing_file, ffprobe
    )
    if (
        phone_segments[0].start_ns != alignment.phone_start_ns
        or tablet_segments[0].start_ns != alignment.tablet_start_ns
    ):
        raise ValueError("Session and segment first-command timestamps disagree")
    origin_ns = min(alignment.phone_start_ns, alignment.tablet_start_ns)
    all_segments = phone_segments + tablet_segments
    if not any(segment.probe is not None for segment in all_segments):
        raise ValueError("No native frames are available on either device")
    common_duration = max(
        end
        for segments in (phone_segments, tablet_segments)
        for segment, (_, end) in zip(segments, segment_intervals(segments, origin_ns))
        if segment.probe is not None
    )
    if any(
        segment.probe is None
        and Decimal(segment.start_ns - origin_ns) / Decimal(1_000_000_000)
        >= common_duration
        for segment in all_segments
    ):
        raise ValueError(
            "Missing trailing segment has no known end; cannot bound its recording gap"
        )
    protected_sources = {segment.path.resolve() for segment in all_segments}
    protected_sources.update((args.phone_video.resolve(), args.tablet_video.resolve()))
    if args.output_video.resolve() in protected_sources:
        raise ValueError("Output must not overwrite a native source recording")
    tablet_probe = next(
        (segment.probe for segment in tablet_segments if segment.probe), None
    )
    tablet_width, tablet_height = (
        video_dimensions(tablet_probe) if tablet_probe else (500, 776)
    )
    phone_filters, phone_sources = build_timeline_graph(
        "phone",
        phone_segments,
        origin_ns,
        common_duration,
        font,
        0,
        350,
        776,
    )
    tablet_filters, tablet_sources = build_timeline_graph(
        "tablet",
        tablet_segments,
        origin_ns,
        common_duration,
        font,
        len(phone_sources),
        920 if tablet_width > tablet_height else 500,
        600 if tablet_width > tablet_height else 776,
    )
    phone_label = (
        f"PHONE / {timing.get('phone_serial', 'unknown source')} / native recording"
    )
    tablet_label = (
        f"TABLET / {timing.get('tablet_serial', 'unknown source')} / native recording"
    )
    filter_graph = build_filter_graph(
        alignment=Alignment(
            alignment.phone_start_ns, alignment.tablet_start_ns, Decimal(0), Decimal(0)
        ),
        duration=common_duration,
        font_file=font,
        phone_label=phone_label,
        tablet_label=tablet_label,
        result_label=args.result_label,
        tablet_is_landscape=tablet_width > tablet_height,
        phone_input="phone_timeline",
        tablet_input="tablet_timeline",
    )
    filter_graph = ";".join(phone_filters + tablet_filters + [filter_graph])

    args.output_video.parent.mkdir(parents=True, exist_ok=True)
    command = [
        ffmpeg,
        "-hide_banner",
        "-y",
        "-filter_complex_threads",
        "2",
        *[
            argument
            for path in phone_sources + tablet_sources
            for argument in ("-threads", "2", "-i", str(path))
        ],
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
        "-threads",
        "2",
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
        "schemaVersion": 2,
        "presentation": {
            "width": CANVAS[0],
            "height": CANVAS[1],
            "frameRate": FRAME_RATE,
            "developmentLabel": DEVELOPMENT_LABEL,
            "resultLabel": args.result_label,
            "tabletLayout": "landscape" if tablet_width > tablet_height else "portrait",
            "timingLabel": TIMING_LABEL,
        },
        "alignment": {
            "phoneFirstSegmentNs": alignment.phone_start_ns,
            "tabletFirstSegmentNs": alignment.tablet_start_ns,
            "phoneDelaySeconds": _seconds(alignment.phone_delay_seconds),
            "tabletDelaySeconds": _seconds(alignment.tablet_delay_seconds),
            "commonDurationSeconds": _seconds(common_duration),
            "basis": "Host timestamp immediately before launching each ADB screenrecord command; first-frame latency is unknown.",
            "overlapPolicy": "A later segment takes over at its recorded command timestamp; original source files retain all frames.",
            "durationPolicy": "Longest estimated device timeline; shorter tails and missing segments remain visible as recording gaps.",
        },
        "sources": {
            **{
                role: {
                    "legacyConcatenationNotUsed": str(video.resolve()),
                    "segmentTiming": {
                        "path": str(
                            (
                                args.timing_file.parent
                                / "recorder-control"
                                / f"{role}-segments.tsv"
                            ).resolve()
                        ),
                        "sha256": sha256(
                            args.timing_file.parent
                            / "recorder-control"
                            / f"{role}-segments.tsv"
                        ),
                    },
                    "segments": [
                        {
                            "path": str(segment.path.resolve()),
                            "sha256": sha256(segment.path) if segment.probe else None,
                            "status": "available" if segment.probe else "missing",
                            "commandStartNs": segment.start_ns,
                            "estimatedStartSeconds": _seconds(start),
                            "estimatedEndSeconds": _seconds(end),
                            "overlappingTailSeconds": _seconds(
                                max(Decimal(0), start + segment.duration - end)
                            ),
                            "probe": segment.probe,
                        }
                        for segment, (start, end) in zip(
                            segments, segment_intervals(segments, origin_ns)
                        )
                    ],
                    "recordingGaps": [
                        {"startSeconds": _seconds(start), "endSeconds": _seconds(end)}
                        for start, end in recording_gaps(
                            segment_intervals(segments, origin_ns), common_duration
                        )
                    ],
                }
                for role, segments, video in (
                    ("phone", phone_segments, args.phone_video),
                    ("tablet", tablet_segments, args.tablet_video),
                )
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
    args.output_video.with_suffix(
        args.output_video.suffix + ".manifest.json"
    ).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    args.output_video.with_suffix(args.output_video.suffix + ".sha256").write_text(
        f"{output_hash}  {args.output_video.name}\n", encoding="utf-8"
    )
    args.output_video.with_suffix(
        args.output_video.suffix + ".ffprobe.json"
    ).write_text(json.dumps(output_probe, indent=2) + "\n", encoding="utf-8")
    print(f"Framed multi-device recording: {args.output_video}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, ValueError, subprocess.CalledProcessError) as error:
        print(f"compose_side_by_side: {error}", file=sys.stderr)
        raise SystemExit(2) from error
