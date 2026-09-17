#!/usr/bin/env python3
"""Install exact CI SDK packages once, retain diagnostics, then validate them."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


SYSTEM_IMAGE = "system-images;android-35;google_apis;x86_64"
PACKAGES = {
    "platform-tools": ("adb",),
    "emulator": ("emulator",),
    "platforms;android-35": ("android.jar",),
    SYSTEM_IMAGE: ("system.img", "ramdisk.img"),
}
CONTEXT_KEYS = ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_SHA")


class PreparationError(ValueError):
    pass


def run_context(context=None):
    source = os.environ if context is None else context
    return {name: source.get(name) for name in CONTEXT_KEYS}


def checked_file(root, relative):
    path = (root / relative).resolve(strict=True)
    if not path.is_relative_to(root) or not path.is_file() or path.stat().st_size == 0:
        raise PreparationError(f"SDK file is empty, missing or outside the selected SDK: {relative}")
    return path


def properties(path):
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, separator, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if not separator or key in result:
            raise PreparationError(f"Ambiguous SDK properties: {path}")
        result[key] = value
    if not result.get("Pkg.Revision"):
        raise PreparationError(f"SDK package revision is absent: {path}")
    return result


def file_record(path):
    return {"bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def command_tools(root):
    folder = Path("cmdline-tools/latest")
    source = checked_file(root, folder / "source.properties")
    return {"sdkmanager": str(checked_file(root, folder / "bin/sdkmanager")),
            "avdmanager": str(checked_file(root, folder / "bin/avdmanager")),
            "sourceProperties": properties(source), "sourceMetadata": file_record(source)}


def validate_packages(root):
    result = {}
    for package, names in PACKAGES.items():
        folder = Path(*package.split(";"))
        metadata = checked_file(root, folder / "package.xml")
        source = checked_file(root, folder / "source.properties")
        tree = ET.fromstring(metadata.read_bytes())
        local = [node for node in tree.iter() if node.tag.rsplit("}", 1)[-1] == "localPackage"]
        if len(local) != 1 or local[0].get("path") != package:
            raise PreparationError(f"Installed package metadata does not match {package}")
        values = properties(source)
        if package == SYSTEM_IMAGE:
            expected = {"AndroidVersion.ApiLevel": "35", "SystemImage.TagId": "google_apis", "SystemImage.Abi": "x86_64"}
            if any(values.get(key) != value for key, value in expected.items()):
                raise PreparationError("Installed system image is not API 35 google_apis x86_64")
        files = {name: checked_file(root, folder / name).stat().st_size for name in names}
        result[package] = {"sourceProperties": values, "packageMetadata": file_record(metadata),
                           "sourceMetadata": file_record(source), "requiredFileBytes": files}
    return result


def verify(sdk_root, preparation_report=None, *, context=None):
    root = sdk_root.resolve(strict=True)
    result = {"status": "validated", "sdkRoot": str(root), "commandTools": command_tools(root),
              "packages": validate_packages(root), "preparationReport": None}
    if preparation_report is not None:
        receipt = json.loads(preparation_report.read_text(encoding="utf-8"))
        if (receipt.get("schemaVersion") != 1 or receipt.get("status") != "prepared"
                or receipt.get("context") != run_context(context)
                or any(receipt.get(key) != result[key] for key in ("sdkRoot", "commandTools", "packages"))):
            raise PreparationError("SDK preparation receipt does not match this run, SDK or installed metadata")
        result["preparationReport"] = str(preparation_report.resolve())
    return result


def prepare(sdk_root, output, *, execute=subprocess.run, context=None):
    # A fresh directory is the attempt journal; even an uncertain installation is
    # never retried into the same evidence directory or silently called at launch.
    output.mkdir(parents=True, exist_ok=False)
    report = {"schemaVersion": 1, "status": "failed", "context": run_context(context),
              "requestedPackages": list(PACKAGES), "commands": {},
              "startedUtc": datetime.now(timezone.utc).isoformat()}

    def invoke(name, command, timeout):
        record = {"arguments": command, "timeoutSeconds": timeout, "attempted": True}
        # Retain intent before starting a write-capable installer.
        (output / f"{name}.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        try:
            completed = execute(command, capture_output=True, timeout=timeout, check=False)
            record["exitCode"] = completed.returncode
            stdout, stderr = completed.stdout, completed.stderr
        except subprocess.TimeoutExpired as error:
            record.update(exitCode=None, error="TimeoutExpired")
            stdout, stderr = error.stdout or b"", error.stderr or b""
        except OSError as error:
            record.update(exitCode=None, error=type(error).__name__)
            stdout, stderr = b"", str(error).encode("utf-8")
        for label, data in (("stdout", stdout), ("stderr", stderr)):
            (output / f"{name}.{label}.log").write_bytes(data)
        report["commands"][name] = record
        (output / f"{name}.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        if record["exitCode"] != 0:
            raise PreparationError(f"{name} failed; original command output retained; no retry is permitted")

    try:
        root = sdk_root.resolve(strict=True)
        report["sdkRoot"] = str(root)
        report["freeBytesBefore"] = shutil.disk_usage(root).free
        report["commandTools"] = command_tools(root)
        manager = report["commandTools"]["sdkmanager"]
        invoke("version", [manager, "--version"], 30)
        invoke("install", [manager, f"--sdk_root={root}", "--verbose", *PACKAGES], 900)
        report["packages"] = validate_packages(root)
        report["status"] = "prepared"
    except (OSError, ValueError, ET.ParseError) as error:
        report["reason"] = str(error)
    finally:
        if "sdkRoot" in report:
            try:
                report["freeBytesAfter"] = shutil.disk_usage(report["sdkRoot"]).free
            except OSError as error:
                report["diskMeasurementError"] = str(error)
        report["completedUtc"] = datetime.now(timezone.utc).isoformat()
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    install = commands.add_parser("prepare")
    install.add_argument("--sdk-root", type=Path, required=True)
    install.add_argument("--output", type=Path, required=True)
    validate = commands.add_parser("verify")
    validate.add_argument("--sdk-root", type=Path, required=True)
    validate.add_argument("--preparation-report", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "verify":
            print(json.dumps(verify(args.sdk_root, args.preparation_report), indent=2))
            return 0
        report = prepare(args.sdk_root, args.output)
        for name in ("version", "install"):
            for stream in ("stdout", "stderr"):
                path = args.output / f"{name}.{stream}.log"
                if path.exists():
                    print(path.read_text(encoding="utf-8", errors="replace"), file=sys.stderr, end="")
        print(json.dumps(report, indent=2))
        return 0 if report["status"] == "prepared" else 1
    except (OSError, ValueError, ET.ParseError) as error:
        print(f"SDK_PACKAGE_PREPARATION_FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
