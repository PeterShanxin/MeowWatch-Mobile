#!/usr/bin/env python3
"""Fetch only the exact successful Actions artifacts pinned by a reviewed edit."""

from __future__ import annotations

import argparse
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess

REPOSITORY = "PeterShanxin/MeowWatch-Mobile"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def source_path(value: object) -> PurePosixPath:
    require(isinstance(value, str) and bool(value), "A relative source path is required")
    require("\\" not in value and ":" not in value, "Use portable relative paths")
    path = PurePosixPath(value)
    require(not path.is_absolute() and all(p not in ("", ".", "..") for p in value.split("/")),
            "Source paths must stay inside the edit package")
    return path


def validate_downloads(edl: dict, manifest: dict) -> list[dict]:
    require(edl.get("purpose") == "submission-edit", "Only native submission edits can be fetched")
    require(manifest.get("schema_version") == 1, "Expected source manifest version 1")
    artifacts = manifest.get("artifacts")
    require(isinstance(artifacts, list) and 1 <= len(artifacts) <= 8,
            "Pin between one and eight source artifacts")
    indexes = {}
    for item in artifacts:
        require(isinstance(item, dict) and set(item) == {"run", "artifact", "commit"},
                "Each source artifact needs exactly run, artifact and commit")
        run, name, commit = item["run"], item["artifact"], item["commit"]
        require(isinstance(run, str) and re.fullmatch(r"[1-9][0-9]{0,19}", run) is not None,
                "Invalid Actions run ID")
        require(isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,150}", name) is not None,
                "An exact artifact name is required; wildcards are not allowed")
        require(isinstance(commit, str) and re.fullmatch(r"[0-9a-f]{40}", commit) is not None,
                "A full source commit is required")
        key = f"sources/{run}/{name}"
        require(key not in indexes, "Duplicate artifact pin")
        indexes[key] = item
    used = set()
    sources = edl.get("sources")
    require(isinstance(sources, dict) and 1 <= len(sources) <= 24,
            "Pin between one and 24 native source files")
    for entry in sources.values():
        require(isinstance(entry, dict), "Invalid source entry")
        parts = source_path(entry.get("path")).parts
        require(len(parts) >= 4, "Source path must name its run and artifact")
        key = "/".join(parts[:3])
        require(key in indexes, "Source path does not match a pinned artifact")
        item = indexes[key]
        require(entry.get("run") == item["run"] and entry.get("commit") == item["commit"],
                "Source run/commit contradicts its artifact pin")
        require(entry.get("kind") == "native-recording", "Only original native recordings are allowed")
        used.add(key)
    require(used == indexes.keys(), "Do not download unused source artifacts")
    for entry in edl.get("timelines", {}).values():
        parts = source_path(entry.get("path")).parts
        require(len(parts) >= 4 and "/".join(parts[:3]) in indexes,
                "Timing evidence must belong to a pinned artifact")
    return artifacts


def verify_run(receipt: dict, item: dict) -> None:
    require(str(receipt.get("databaseId")) == item["run"], "Actions returned a different run")
    require(receipt.get("headSha") == item["commit"], "Actions source commit does not match the edit")
    require(receipt.get("conclusion") == "success", "Source workflow did not complete successfully")


def prepare(edl_path: Path, output: Path, repository_root: Path) -> None:
    edl_path = edl_path.resolve()
    require(edl_path.is_relative_to(repository_root.resolve()), "Select a checked-in repository edit")
    manifest_path = edl_path.with_suffix(".sources.json")
    require(manifest_path.resolve().is_relative_to(repository_root.resolve()),
            "Source manifest must stay inside the repository")
    edl = json.loads(edl_path.read_text(encoding="utf-8-sig"))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    artifacts = validate_downloads(edl, manifest)
    output.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(edl_path, output / "edit.json")
    shutil.copyfile(manifest_path, output / "edit.sources.json")
    receipts = []
    for item in artifacts:
        response = subprocess.run(
            ["gh", "run", "view", item["run"], "--repo", REPOSITORY,
             "--json", "databaseId,headSha,url,conclusion"],
            check=True, capture_output=True, text=True, timeout=60,
        )
        receipt = json.loads(response.stdout)
        verify_run(receipt, item)
        receipts.append({**receipt, "artifact": item["artifact"]})
        (output / "source-runs.json").write_text(json.dumps(receipts, indent=2) + "\n", encoding="utf-8")
        subprocess.run(
            ["gh", "run", "download", item["run"], "--repo", REPOSITORY,
             "--name", item["artifact"], "--dir", str(output / "sources" / item["run"] / item["artifact"])],
            check=True, timeout=300,
        )
    # Full file hashes, media dimensions, coverage and shared clocks are checked
    # by compose.py before any source can enter the film.


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("edl", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    prepare(args.edl, args.output, Path(__file__).resolve().parents[2])
