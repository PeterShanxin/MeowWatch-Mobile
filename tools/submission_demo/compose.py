#!/usr/bin/env python3
"""A small, evidence-preserving 1080p editor for the MeowWatch submission film."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ASSETS = {
    "logo": REPO / "assets/brand/meowwatch-1024.png",
    "sans": REPO / "assets/fonts/DMSans.ttf",
    "serif": REPO / "assets/fonts/DMSerifDisplay.ttf",
}
FPS = 30
NAVY, CREAM, BLUE, FRAME = "0x102A43", "0xFFF5DF", "0x5BA8F5", "0x061525"
SMOKE = "SYNTHETIC TEST FIXTURE / NOT APP EVIDENCE"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    require(isinstance(data, dict), f"Expected an object: {path}")
    return data


def number(value: object, label: str) -> float:
    require(isinstance(value, (int, float)) and not isinstance(value, bool),
            f"{label} must be a finite JSON number")
    require(math.isfinite(value), f"{label} must be finite")
    return float(value)


def text(value: object, label: str, maximum: int = 100) -> str:
    require(isinstance(value, str) and 0 < len(value) <= maximum,
            f"{label} must contain 1..{maximum} characters")
    require(all(ord(c) >= 32 for c in value), f"{label} contains control characters")
    return value


def pinned(entry: dict, root: Path) -> tuple[Path, str]:
    path = (root / text(entry.get("path"), "path", 2000)).resolve()
    require(path.is_file(), f"Missing source: {path}")
    expected = entry.get("sha256", "")
    require(isinstance(expected, str) and re.fullmatch(r"[0-9a-f]{64}", expected) is not None,
            f"A fixed lowercase SHA256 is required: {path}")
    actual = sha256(path)
    require(actual == expected, f"SHA256 mismatch: {path}")
    return path, actual


def probe(path: Path, ffprobe: str) -> dict:
    result = subprocess.run(
        [ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)],
        check=True, capture_output=True, text=True, encoding="utf-8",
    )
    data = json.loads(result.stdout)
    videos = [s for s in data["streams"] if s.get("codec_type") == "video"]
    require(len(videos) == 1, f"Exactly one video stream required: {path}")
    stream = videos[0]
    # Container duration can include a longer audio tail; only video coverage counts.
    duration = float(stream.get("duration", "nan"))
    require(math.isfinite(duration) and duration > 0, f"Invalid video duration: {path}")
    require(stream.get("sample_aspect_ratio", "1:1") in ("1:1", "N/A"),
            f"Non-square pixels are unsupported: {path}")
    rotation = [side.get("rotation", 0) for side in stream.get("side_data_list", [])]
    rotation.append(stream.get("tags", {}).get("rotate", 0))
    require(all(float(angle) % 360 == 0 for angle in rotation),
            f"Rotated metadata is unsupported; use the original oriented capture: {path}")
    return {"width": stream["width"], "height": stream["height"], "duration": duration,
            "codec": stream["codec_name"], "frame_rate": stream["avg_frame_rate"],
            "raw": data}


def source_entry(path: Path, ffprobe: str) -> dict:
    actual = probe(path, ffprobe)
    return {"path": str(path.resolve()), "sha256": sha256(path),
            "width": actual["width"], "height": actual["height"],
            "duration_seconds": actual["duration"]}


def interval(shot: dict) -> tuple[float, float]:
    start, end = number(shot.get("in"), "in"), number(shot.get("out"), "out")
    require(0 <= start < end, "Clip must have 0 <= in < out")
    require(number(shot.get("speed"), "speed") == 1, "Only 1x footage is supported")
    return start, end


def segment_window(timing: dict, role: str, source: dict, start: float, end: float) -> float:
    """Resolve a common window into one original segment, never bridge a gap."""
    segments = timing.get("sources", {}).get(role, {}).get("segments", [])
    matches = [s for s in segments if s.get("sha256") == source["sha256"]
               and Path(s.get("path", "").replace("\\", "/")).name == source["path"].name]
    require(len(matches) == 1, f"Unique {role} source missing from pinned timing manifest")
    segment = matches[0]
    require(segment.get("status") == "available", f"Unavailable {role} segment")
    low, high = float(segment["estimatedStartSeconds"]), float(segment["estimatedEndSeconds"])
    require(math.isfinite(low) and math.isfinite(high) and 0 <= low < high,
            f"Invalid {role} timing interval")
    require(low <= start and end <= high,
            f"{role} window crosses a recording gap, overlap takeover or segment boundary")
    for gap in timing["sources"][role].get("recordingGaps", []):
        require(end <= float(gap["startSeconds"]) or start >= float(gap["endSeconds"]),
                f"{role} window intersects a recording gap")
    return start - low


def validate(edl_path: Path, ffprobe: str = "ffprobe") -> dict:
    edl_path = edl_path.resolve()
    edl = read_json(edl_path)
    require(edl.get("schema_version") == 1, "Expected EDL schema_version 1")
    require(edl.get("purpose") in ("submission-edit", "synthetic-smoke"), "Invalid EDL purpose")
    synthetic = edl["purpose"] == "synthetic-smoke"
    sources, timelines, protected = {}, {}, {edl_path: sha256(edl_path)}
    for name, entry in edl.get("sources", {}).items():
        path, digest = pinned(entry, edl_path.parent)
        actual = probe(path, ffprobe)
        require((entry.get("width"), entry.get("height")) == (actual["width"], actual["height"]),
                f"Dimensions disagree with the EDL: {name}")
        require(16 <= actual["width"] <= 8192 and 16 <= actual["height"] <= 8192,
                f"Unsupported dimensions: {name}")
        require(entry.get("kind") == ("synthetic-fixture" if synthetic else "native-recording"),
                "Synthetic and native recordings cannot be mixed or relabeled by this editor")
        for key in ("runtime", "run", "commit"):
            text(entry.get(key), f"{name}.{key}", 60 if key == "runtime" else 120)
        if not synthetic:
            require(re.fullmatch(r"[0-9a-f]{40}", entry["commit"]) is not None,
                    f"Native source requires its full lowercase Git commit: {name}")
            require(not any(marker in entry["run"].upper() for marker in ("REPLACE", "TODO", "UNKNOWN")),
                    f"Native source run is unresolved: {name}")
        sources[name] = {**entry, "path": path, "probe": actual}
        protected[path] = digest
    for name, entry in edl.get("timelines", {}).items():
        path, digest = pinned(entry, edl_path.parent)
        timing = read_json(path)
        require(timing.get("schemaVersion") == 2, "Paired clips require a schema-v2 timing manifest")
        timelines[name] = timing
        protected[path] = digest
    shots, seen, used, elapsed = [], set(), set(), 0.0
    for original in edl.get("shots", []):
        shot = dict(original)
        name = text(shot.get("id"), "shot.id", 64)
        require(name not in seen, f"Duplicate shot id: {name}")
        seen.add(name)
        text(shot.get("title"), f"{name}.title", 48)
        text(shot.get("caption"), f"{name}.caption", 132)
        kind = shot.get("kind")
        require(kind in ("card", "single", "pair"), f"Unsupported shot kind: {kind}")
        common = {"id", "kind", "title", "caption"}
        allowed = {
            "card": {"duration"},
            "single": {"source", "in", "out", "speed", "device", "label", "disclosure"},
            "pair": {"timeline", "phone", "tablet", "in", "out", "speed", "phone_label", "tablet_label", "disclosure"},
        }
        require(not set(shot) - common - allowed[kind], f"Unsupported shot fields: {set(shot) - common - allowed[kind]}")
        clips = []
        if kind == "card":
            duration = number(shot.get("duration"), "card.duration")
        else:
            start, end = interval(shot)
            duration = end - start
            if shot.get("disclosure"):
                text(shot["disclosure"], f"{name}.disclosure", 110)
            if kind == "single":
                require(shot.get("device") in ("phone", "tablet"), "single.device is phone or tablet")
                role_sources = [(shot["device"], shot.get("source"))]
            else:
                require(shot.get("timeline") in timelines, "A pinned timeline is required for paired clips")
                role_sources = [(role, shot.get(role)) for role in ("phone", "tablet")]
            for role, source_id in role_sources:
                require(source_id in sources, f"Unresolved source: {source_id}")
                source = sources[source_id]
                used.add(source_id)
                local_in = start if kind == "single" else segment_window(
                    timelines[shot["timeline"]], role, source, start, end)
                require(local_in >= 0 and local_in + duration <= source["probe"]["duration"] + 0.000001,
                        f"Source range exceeds real footage: {source_id}")
                label = shot.get("label") if kind == "single" else shot.get(f"{role}_label")
                text(label, f"{name}.{role} label", 42)
                width, height = source["probe"]["width"], source["probe"]["height"]
                require((width < height) if role == "phone" else (width > height),
                        f"Expected portrait phone / landscape tablet: {source_id}")
                clips.append({"role": role, "source": source_id, "in": local_in,
                              "out": local_in + duration, "label": label})
            if kind == "pair":
                pair = [sources[item["source"]] for item in clips]
                require(pair[0]["run"] == pair[1]["run"] and pair[0]["commit"] == pair[1]["commit"],
                        "Paired sources must share the same run and commit")
                require(pair[0]["sha256"] != pair[1]["sha256"], "Paired clips require two different source recordings")
        require(0 < duration <= 60, "Each shot must last more than 0 and at most 60 seconds")
        require(abs(duration * FPS - round(duration * FPS)) < 0.00001,
                "Output shot duration must be an exact number of 30fps frames")
        shots.append({**shot, "duration": duration, "clips": clips,
                      "output_in": elapsed, "output_out": elapsed + duration})
        elapsed += duration
    require(shots and 0 < elapsed < 120, "The edit must be nonempty and strictly under 120 seconds")
    require(used, "The edit must contain recorded footage, not only graphic cards")
    require(used == set(sources), "Remove unused sources from the EDL")
    for path in ASSETS.values():
        require(path.is_file(), f"Bundled brand asset missing: {path}")
        protected[path] = sha256(path)
    return {"edl": edl, "edl_path": edl_path, "sources": sources, "shots": shots,
            "duration": elapsed, "protected": protected, "synthetic": synthetic}


def fit(source: dict, box: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    x, y, width, height = box
    scale = min(width / source["probe"]["width"], height / source["probe"]["height"])
    fitted_w = int(source["probe"]["width"] * scale) // 2 * 2
    fitted_h = int(source["probe"]["height"] * scale) // 2 * 2
    return x + (width - fitted_w) // 2, y + (height - fitted_h) // 2, fitted_w, fitted_h


def render_shot(plan: dict, shot: dict, folder: Path, ffmpeg: str, preset: str) -> Path:
    folder.mkdir()
    for name, asset in ASSETS.items():
        shutil.copyfile(asset, folder / (name + asset.suffix))
    command = [ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin",
               "-filter_complex_threads", "1", "-loop", "1", "-i", "logo.png"]
    for clip in shot["clips"]:
        command.extend(["-noautorotate", "-i", str(plan["sources"][clip["source"]]["path"])])
    graph = [f"color=c={NAVY}:s=1920x1080:r=30:d={shot['duration']:.9f},format=rgb24[bg]"]
    current, counter = "bg", 0

    def effect(expression: str) -> None:
        nonlocal current, counter
        counter += 1
        graph.append(f"[{current}]{expression}[layer{counter}]")
        current = f"layer{counter}"

    def words(value: str, x: str | int, y: int, size: int, color: str = CREAM,
              font: str = "sans", wrap: int | None = None) -> None:
        lines = [value]
        if wrap:
            lines = textwrap.wrap(value, width=wrap, break_long_words=False, break_on_hyphens=False)
            require(len(lines) <= 3 and all(len(line) <= wrap for line in lines), "Copy exceeds reserved text area")
        # Variable font line metrics differ across ffmpeg builds. Place each line
        # explicitly so no descender/line-gap metadata can run into the device/footer.
        for line_number, line in enumerate(lines):
            name = f"text-{counter}.txt"
            (folder / name).write_text(line, encoding="utf-8")
            effect(f"drawtext=fontfile={font}.ttf:textfile={name}:expansion=none:"
                   f"fontcolor={color}:fontsize={size}:x={x}:y={y + line_number * (size + 12)}")

    if shot["kind"] == "card":
        logo_size, logo_x, logo_y = 176, 120, 298
        words("MEOWWATCH MOBILE", 350, 303, 28, BLUE)
        words(shot["title"], 350, 362, 58, font="serif", wrap=37)
        words(shot["caption"], 350, 566, 32, wrap=64)
    else:
        logo_size, logo_x, logo_y = 52, 64, 40
        words("MeowWatch Mobile", 136, 50, 26)
        if shot["kind"] == "pair":
            words(shot["title"], "(w-text_w)/2", 102, 34)
            boxes = {"phone": (150, 207, 340, 680), "tablet": (670, 251, 1090, 610)}
        elif shot["device"] == "phone":
            words(shot["title"], 120, 340, 54, font="serif", wrap=27)
            words(shot["caption"], 120, 540, 32, wrap=40)
            boxes = {"phone": (1160, 150, 360, 780)}
        else:
            words(shot["title"], "(w-text_w)/2", 111, 38)
            boxes = {"tablet": (400, 210, 1120, 650)}
        for index, clip in enumerate(shot["clips"], start=1):
            source = plan["sources"][clip["source"]]
            x, y, width, height = fit(source, boxes[clip["role"]])
            effect(f"drawbox=x={x-12}:y={y-12}:w={width+24}:h={height+24}:color={BLUE}:t=fill")
            effect(f"drawbox=x={x-11}:y={y-11}:w={width+22}:h={height+22}:color={FRAME}:t=fill")
            # Keep pre-cut frames: a VFR frame can still be on screen at the
            # requested cut. Rebase the source CLOCK, never the first retained
            # frame. The 30fps canvas samples the latest source PTS <= its clock;
            # validated coverage and the canvas frame limit bound the end.
            # Quantize changes upward to the canvas tick so framesync cannot
            # round a future VFR frame back onto an earlier output frame.
            graph.append(f"[{index}:v:0]settb=AVTB,"
                         f"setpts='ceil((PTS-STARTPTS-{clip['in']:.9f}/TB)*TB*30-0.000001)/(30*TB)',"
                         "settb=1/30,"
                         f"scale={width}:{height}:flags=lanczos,setsar=1,format=rgb24[device{index}]")
            counter += 1
            graph.append(f"[{current}][device{index}]overlay=x={x}:y={y}:"
                         f"eof_action=pass:repeatlast=0:ts_sync_mode=default:format=rgb[layer{counter}]")
            current = f"layer{counter}"
            words(clip["label"], x, y - 53, 25)
        if shot["kind"] == "pair" or shot.get("device") == "tablet":
            words(shot["caption"], "(w-text_w)/2", 916, 26, wrap=90)
        if shot.get("disclosure"):
            words(shot["disclosure"], 64, 982, 20, BLUE)
        runtimes = " / ".join(dict.fromkeys(plan["sources"][clip["source"]]["runtime"] for clip in shot["clips"]))
        if shot["kind"] == "pair":
            runtimes += " · approximate recording alignment · 1×"
        words(runtimes, 64, 1014, 18, BLUE)
    graph.append(f"[0:v:0]scale={logo_size}:{logo_size}[mark]")
    graph.append(f"[{current}][mark]overlay={logo_x}:{logo_y}:shortest=1:format=rgb[branded]")
    current = "branded"
    if plan["synthetic"]:
        effect(f"drawbox=x=0:y=0:w=1920:h=34:color={CREAM}:t=fill")
        words(SMOKE, "(w-text_w)/2", 4, 22, NAVY)
    # Cards and Android captures can carry different color metadata. Composite
    # in RGB, then perform one explicit delivery conversion for every shot.
    graph.append(f"[{current}]scale=out_color_matrix=bt709:out_range=tv,format=yuv420p,"
                 "setparams=range=limited:colorspace=bt709:color_primaries=bt709:color_trc=bt709[out]")
    (folder / "filter.txt").write_text(";\n".join(graph), encoding="utf-8")
    output = folder / "shot.mp4"
    command += ["-filter_complex_script", "filter.txt", "-map", "[out]", "-an",
                "-frames:v", str(round(shot["duration"] * FPS)), "-c:v", "libx264",
                "-threads", "2", "-preset", preset, "-crf", "19", "-pix_fmt", "yuv420p",
                "-movflags", "+faststart", str(output)]
    subprocess.run(command, cwd=folder, check=True)
    return output


def render(edl_path: Path, output: Path, ffmpeg: str = "ffmpeg", ffprobe: str = "ffprobe",
           preset: str = "medium") -> dict:
    plan = validate(edl_path, ffprobe)
    output = output.resolve()
    require(output.suffix.lower() == ".mp4", "Output must be an MP4")
    sidecars = [output.with_suffix(output.suffix + ending)
                for ending in (".manifest.json", ".edl.json", ".sha256")]
    for destination in [output, *sidecars]:
        require(not destination.exists() and destination not in plan["protected"],
                f"Refusing to overwrite an existing file: {destination}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".submission-edit-", dir=output.parent) as temporary:
        work = Path(temporary).resolve()
        clips = [render_shot(plan, shot, work / f"shot-{index:03d}", ffmpeg, preset)
                 for index, shot in enumerate(plan["shots"])]
        (work / "concat.txt").write_text(
            "".join(f"file 'shot-{index:03d}/shot.mp4'\n" for index in range(len(clips))), encoding="utf-8")
        composed = work / "composed.mp4"
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-f", "concat",
                        "-safe", "1", "-i", "concat.txt", "-c", "copy", "-an", "-movflags", "+faststart",
                        str(composed)], cwd=work, check=True)
        actual = probe(composed, ffprobe)
        require((actual["width"], actual["height"], actual["codec"], actual["frame_rate"])
                == (1920, 1080, "h264", "30/1"), "Output format verification failed")
        require(abs(actual["duration"] - plan["duration"]) <= 1 / FPS and actual["duration"] < 120,
                "Output duration verification failed")
        for path, digest in plan["protected"].items():
            require(sha256(path) == digest, f"Input changed during rendering: {path}")
        digest = sha256(composed)
        manifest = {
            "schema_version": 1, "purpose": plan["edl"]["purpose"],
            "acceptance": "Synthetic fixture only" if plan["synthetic"] else "Editorial output; native acceptance and visual review remain external",
            "presentation": "1x, direct cuts, proportional fit, no source crop or overlays inside device content; silent",
            "sampling": "30fps canvas samples the latest source frame at or before each requested source clock; VFR holds retained, no cut-point rebase",
            "color": "RGB composition; consistent limited-range BT.709 yuv420p delivery conversion",
            "alignment": "Pinned host-command timeline; not frame-accurate synchronization proof",
            "edl_sha256": plan["protected"][plan["edl_path"]],
            "inputs": [{"path": str(path), "sha256": value} for path, value in plan["protected"].items()],
            "sources": {name: {**source, "path": str(source["path"])} for name, source in plan["sources"].items()},
            "shots": plan["shots"], "output": {"path": str(output), "sha256": digest, "probe": actual},
            "ffmpeg_version": subprocess.check_output([ffmpeg, "-version"], text=True).splitlines()[0],
        }
        # Exclusive creation prevents accidental replacement even if another process creates the target.
        with output.open("xb") as target, composed.open("rb") as source:
            shutil.copyfileobj(source, target)
        for path, content in zip(sidecars, [json.dumps(manifest, indent=2) + "\n",
                                            json.dumps(plan["edl"], indent=2) + "\n",
                                            f"{digest}  {output.name}\n"]):
            with path.open("x", encoding="utf-8") as target:
                target.write(content)
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    sub = parser.add_subparsers(dest="command", required=True)
    inspect = sub.add_parser("inspect", help="Print actual source dimensions, duration and SHA256")
    inspect.add_argument("files", nargs="+", type=Path)
    check = sub.add_parser("validate", help="Validate all pinned EDL inputs without rendering")
    check.add_argument("edl", type=Path)
    build = sub.add_parser("render", help="Render a new MP4 and evidence sidecars")
    build.add_argument("edl", type=Path)
    build.add_argument("output", type=Path)
    build.add_argument("--preset", choices=("ultrafast", "fast", "medium"), default="medium")
    args = parser.parse_args(argv)
    if args.command == "inspect":
        print(json.dumps([source_entry(path, args.ffprobe) for path in args.files], indent=2))
    elif args.command == "validate":
        plan = validate(args.edl, args.ffprobe)
        print(f"Validated {len(plan['shots'])} shots / {plan['duration']:.3f}s / {plan['edl']['purpose']}")
    else:
        manifest = render(args.edl, args.output, args.ffmpeg, args.ffprobe, args.preset)
        print(f"Rendered {args.output}: {manifest['output']['sha256']}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print(f"submission_demo: {error}", file=sys.stderr)
        raise SystemExit(2) from error
