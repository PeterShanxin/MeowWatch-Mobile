#!/usr/bin/env python3
"""Build the independent, shell-controlled audio focus helper APK."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from typing import Sequence
import zipfile


SOURCE = Path(__file__).resolve().parent / "helper"
DEFAULT_OUTPUT = Path("build/android-interruption-helper")


def build(sdk: Path, java_home: Path, output: Path, *, platform: int = 35,
          build_tools: str = "36.0.0") -> Path:
    if output.exists() and any(output.iterdir()):
        raise ValueError("audio focus helper build directory must start empty")
    suffix = ".exe" if os.name == "nt" else ""
    java = java_home / "bin" / f"java{suffix}"
    javac = java_home / "bin" / f"javac{suffix}"
    keytool = java_home / "bin" / f"keytool{suffix}"
    platform_jar = sdk / "platforms" / f"android-{platform}" / "android.jar"
    tools = sdk / "build-tools" / build_tools
    aapt = tools / f"aapt2{suffix}"
    zipalign = tools / f"zipalign{suffix}"
    d8 = tools / "lib" / "d8.jar"
    signer = tools / "lib" / "apksigner.jar"
    for required in (java, javac, keytool, platform_jar, aapt, zipalign, d8, signer):
        if not required.is_file():
            raise ValueError(f"required installed build tool is missing: {required.name}")
    output.mkdir(parents=True, exist_ok=True)
    classes, dex = output / "classes", output / "dex"
    classes.mkdir()
    dex.mkdir()
    commands: list[dict[str, object]] = []

    def run(label: str, arguments: list[str | Path]) -> None:
        completed = subprocess.run([str(value) for value in arguments], capture_output=True,
                                   check=False, timeout=120)
        commands.append({"step": label, "exitCode": completed.returncode})
        (output / f"{label}.log").write_bytes(completed.stdout + completed.stderr)
        if completed.returncode:
            raise RuntimeError(f"audio focus helper build failed at {label}; inspect its local build log")

    sources = sorted((SOURCE / "src").rglob("*.java"))
    run("javac", [javac, "-encoding", "UTF-8", "-source", "8", "-target", "8",
                  "-bootclasspath", platform_jar, "-d", classes, *sources])
    run("dex", [java, "-cp", d8, "com.android.tools.r8.D8", "--lib", platform_jar,
                "--min-api", "26", "--output", dex, *sorted(classes.rglob("*.class"))])
    unsigned, aligned = output / "unsigned.apk", output / "aligned.apk"
    run("package", [aapt, "link", "-I", platform_jar, "--manifest",
                    SOURCE / "AndroidManifest.xml", "-o", unsigned])
    with zipfile.ZipFile(unsigned, "a", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.write(dex / "classes.dex", "classes.dex")
    run("align", [zipalign, "-f", "4", unsigned, aligned])
    keystore = output / "debug.keystore"
    run("debug-key", [keytool, "-genkeypair", "-keystore", keystore, "-storepass", "android",
                      "-keypass", "android", "-alias", "androiddebugkey", "-keyalg", "RSA",
                      "-keysize", "2048", "-validity", "365", "-dname",
                      "CN=Android Debug,O=MeowWatch Test,C=US"])
    apk = output / "audio-focus-probe.apk"
    run("sign", [java, "-jar", signer, "sign", "--ks", keystore, "--ks-key-alias",
                 "androiddebugkey", "--ks-pass", "pass:android", "--key-pass", "pass:android",
                 "--out", apk, aligned])
    run("verify", [java, "-jar", signer, "verify", "--verbose", apk])
    run("manifest", [aapt, "dump", "xmltree", "--file", "AndroidManifest.xml", apk])
    manifest = (output / "manifest.log").read_text(encoding="utf-8")
    if 'targetPackage' in manifest or 'android.permission.DUMP' not in manifest:
        raise RuntimeError("focus helper must not instrument another package or expose unrestricted commands")
    if ('com.meowwatch.audio_focus_probe' not in manifest
            or re.search(r':foregroundServiceType[^\n]*=0x0*2\b', manifest) is None):
        raise RuntimeError("packaged helper service does not match the reviewed manifest")
    (output / "build.json").write_text(json.dumps({
        "androidPlatform": platform, "androidBuildTools": build_tools,
        "apkSha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
        "sourceSha256": {str(path.relative_to(SOURCE)): hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in [SOURCE / "AndroidManifest.xml", *sources]},
        "servicePackage": "com.meowwatch.audio_focus_probe",
        "commands": commands,
    }, indent=2), encoding="utf-8")
    return apk


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, default=os.environ.get("ANDROID_SDK_ROOT", os.environ.get("ANDROID_HOME")))
    parser.add_argument("--java-home", type=Path, default=os.environ.get("JAVA_HOME"))
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--platform", type=int, default=35)
    parser.add_argument("--build-tools", default="36.0.0")
    args = parser.parse_args(argv)
    if args.sdk is None:
        parser.error("--sdk or ANDROID_HOME/ANDROID_SDK_ROOT is required")
    java_home = args.java_home
    if java_home is None:
        found = shutil.which("javac")
        if found:
            java_home = Path(found).resolve().parent.parent
    if java_home is None:
        parser.error("--java-home, JAVA_HOME or installed javac is required")
    print(build(args.sdk, java_home, args.output, platform=args.platform, build_tools=args.build_tools))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
