"""Prepare an explicitly selected, disposable Flutter semantics diagnostic SDK."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys


HERE = Path(__file__).resolve().parent
OBJECT = Path("packages/flutter/lib/src/rendering/object.dart")
VERSION = Path("bin/cache/flutter.version.json")
FRAMEWORK_REVISION = "559ffa3f75e7402d65a8def9c28389a9b2e6fe42"
UPSTREAM_HEAD = "65e4783d8a1019029da88ee2435892ef638a9937"
PATCH_SHA256 = "a6b442e1d0322b479b993128775be69d3ec781f8d490486c1047b1ce6edd0b10"
SOURCE_HASHES = {
    # Exact file bytes in the official 3.44.0 source, in LF and CRLF form.
    "1e9b767b32c2bcb4ed48b5193360518dbcb6b1ccbb0919f19e8b0e2c12f6c5f5":
        "88d1c5f62c4f0234d4b15422b83114bf3b7db8c10d3d405d1e9949a79d777f6b",
    "e5904ebd3bce95882f2ba985aa5959ffa380eddd4348890281c9678f5d1b1ca5":
        "e231fd1f0387f104102f0458024bcc82eb2a566000b152b50e3f55eb60cf6423",
}


class Refused(RuntimeError):
    pass


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def apply_fixed_patch(original: bytes) -> bytes:
    expected = SOURCE_HASHES.get(sha256(original))
    if expected is None:
        raise Refused("object.dart does not match unmodified Flutter 3.44.0")
    patch = (HERE / "object.dart.upstream.patch").read_bytes().replace(b"\r\n", b"\n")
    if sha256(patch) != PATCH_SHA256:
        raise Refused("Checked-in upstream patch hash does not match")
    text = original.decode("utf-8").replace("\r\n", "\n")
    hunks = re.split(r"(?m)^@@[^\n]*\n", patch.decode("utf-8"))[1:]
    if len(hunks) != 2:
        raise Refused("Expected exactly two pinned upstream hunks")
    for hunk in hunks:
        lines = hunk.splitlines(keepends=True)
        old = "".join(line[1:] for line in lines if line.startswith((" ", "-")))
        new = "".join(line[1:] for line in lines if line.startswith((" ", "+")))
        if text.count(old) != 1:
            raise Refused("Upstream patch context is not unique")
        text = text.replace(old, new, 1)
    if b"\r\n" in original:
        text = text.replace("\n", "\r\n")
    result = text.encode("utf-8")
    if sha256(result) != expected:
        raise Refused("Patched object.dart does not match the fixed output hash")
    return result


def check_source(source: Path) -> bytes:
    version = json.loads((source / VERSION).read_text(encoding="utf-8"))
    if (version.get("frameworkVersion") != "3.44.0"
            or version.get("frameworkRevision") != FRAMEWORK_REVISION):
        raise Refused("Expected official Flutter 3.44.0 framework revision")
    target = (source / OBJECT).resolve(strict=True)
    if not target.is_relative_to(source):
        raise Refused("Source object.dart escapes the explicit SDK")
    return target.read_bytes()


def validate_destination(source: Path, output: Path, env: dict[str, str]) -> None:
    if env.get("GITHUB_ACTIONS") != "true" or env.get("RUNNER_ENVIRONMENT") != "github-hosted":
        raise Refused("SDK preparation is restricted to a GitHub-hosted Actions runner; use --check locally")
    if not env.get("RUNNER_TEMP"):
        raise Refused("RUNNER_TEMP is required")
    temp = Path(env["RUNNER_TEMP"]).resolve(strict=True)
    if output == temp or not output.is_relative_to(temp):
        raise Refused("Output SDK must be a new directory strictly inside RUNNER_TEMP")
    if output.exists() or output.is_symlink():
        raise Refused("Output SDK already exists")
    if output.is_relative_to(source) or source.is_relative_to(output):
        raise Refused("Source and output SDK paths overlap")


def prepare(source: Path, output: Path | None, *, check: bool,
            report: dict, env: dict[str, str]) -> None:
    if not source.is_absolute() or (output is not None and not output.is_absolute()):
        raise Refused("SDK paths must be explicitly absolute")
    source = source.resolve(strict=True)
    original = check_source(source)
    report["sourceObjectSha256Before"] = sha256(original)
    patched = apply_fixed_patch(original)
    report["candidateObjectSha256"] = sha256(patched)
    if check:
        report["status"] = "checked-only-no-sdk-written"
        return
    if output is None:
        raise Refused("--output-sdk is required for CI preparation")
    output = output.resolve()
    validate_destination(source, output, env)
    report["outputSdk"] = str(output)
    report["status"] = "copying-sdk"
    try:
        # copy2 creates independent files; never hard-link the cached SDK.
        shutil.copytree(source, output, copy_function=shutil.copy2, symlinks=False)
        target = (output / OBJECT).resolve(strict=True)
        if not target.is_relative_to(output) or target.stat().st_nlink != 1:
            raise Refused("Copied object.dart is not an independent file inside the output SDK")
        if target.read_bytes() != original:
            raise Refused("Copied object.dart differs from the verified source")
        target.write_bytes(patched)
        if sha256(target.read_bytes()) != report["candidateObjectSha256"]:
            raise Refused("Written candidate object.dart hash differs")
    finally:
        report["sourceObjectSha256After"] = sha256((source / OBJECT).read_bytes())
        if report["sourceObjectSha256After"] != report["sourceObjectSha256Before"]:
            raise Refused("Cached source SDK changed during preparation")
    report["status"] = "candidate-prepared-not-native-validated"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-sdk", type=Path, required=True)
    parser.add_argument("--output-sdk", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--check", action="store_true", help="Verify only; never copy or change an SDK")
    args = parser.parse_args(argv)
    report_path = args.report.resolve()
    for sdk in (args.source_sdk, args.output_sdk):
        if sdk is not None and report_path.is_relative_to(sdk.resolve()):
            parser.error("--report must be outside both SDK directories")
    report = {
        "schema": 1,
        "mode": "unmerged-semantics-candidate",
        "status": "started",
        "preparedUtc": datetime.now(timezone.utc).isoformat(),
        "flutterVersion": "3.44.0",
        "frameworkRevision": FRAMEWORK_REVISION,
        "upstreamPr": "https://github.com/flutter/flutter/pull/190431",
        "upstreamHead": UPSTREAM_HEAD,
        "patchSha256": PATCH_SHA256,
        "nativeGeometryFixProven": False,
    }
    code = 0
    try:
        prepare(args.source_sdk, args.output_sdk, check=args.check, report=report, env=dict(os.environ))
    except (OSError, ValueError, Refused) as error:
        report["status"] = "refused-or-failed"
        report["error"] = str(error)
        print(f"Semantics candidate refused: {error}", file=sys.stderr)
        code = 1
    finally:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if code == 0:
        print(f"UNMERGED SEMANTICS DIAGNOSTIC: {report['status']}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
