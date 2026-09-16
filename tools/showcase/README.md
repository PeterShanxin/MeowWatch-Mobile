# Local development showcase

This tool serves a local-only browser page that displays real Android frames from `adb exec-out screencap -p`, a truthful waiting state when no device is attached, verified progress from `.local/showcase/status.json`, and downloaded CI screenshots/video from `.local/showcase/evidence/`. When adb reports multiple sources, their actual frames are composed side by side (or in a compact grid) with simple bezels and labels identifying the model and whether adb reports an emulator or physical device. The bezel never substitutes synthetic screen content. A retained frame becomes visibly `STALE` after five seconds without a successful capture, and late responses cannot replace newer frames.

When adb reports no connected source, the read-only **No-ADB canvas source** selector can show the latest matching `phone-<state>.png` and `tablet-<state>.png` pair for `home`, `onboarding`, or `player` from `.local/visual-review/`. The backend serves only those six exact filenames. The canvas permanently labels this fallback **Flutter UI preview · test renderer**, **injected unit state**, and **not Android plugin/runtime evidence**, with each source filename and modification timestamp. These images must be produced by the repository's Flutter rendered-review test; the showcase does not synthesize replacement app UI. Actual downloaded Android CI screenshots and video remain separate under `.local/showcase/evidence/`.

Opening the page starts a bounded `canvas.captureStream(2)` recording at 900 kbps. The canvas contains only the native Android frame (or explicit waiting state), source label, and timestamp. It cannot capture the desktop, other windows, microphone, or development history from before the page opened.

The browser sends a WebM chunk every 30 seconds using an ordered, bounded retry queue. Chunks are durably appended to one session file under `.local/showcase/recordings/`; identical sequence/size/SHA-256 replays are accepted without appending twice, while changed replays are rejected. The adjacent manifest records chunk timestamps, hashes, byte counts, and browser-heartbeat gaps. The recorded canvas includes the current verified status headline, capture timestamp, and a precise source classification. **Stop safely** waits for the final `MediaRecorder` event and all uploads before marking a session complete. Closing the page, losing it, or exhausting upload retries marks the session `interrupted` and `unflushed` rather than claiming the last partial interval was saved.

Run from the repository root:

```powershell
python tools/showcase/server.py --port 8765 --token <random-secret>
```

Pass `--adb <path>` to select an exact executable. Otherwise the server checks `ANDROID_SDK_ROOT`, `ANDROID_HOME`, `%LOCALAPPDATA%\Android\Sdk`, and finally `adb` on `PATH`.

The server prints the exact tokenized URL. It binds only to `127.0.0.1`, rejects unexpected `Host` and `Origin` values, requires the launch token for every request, and signs each recording session with a separate bearer secret. Files remain local; the tool provides no tunnel or LAN listener.

The main development process may update `.local/showcase/status.json` atomically. Put actual downloaded CI `.png`, `.jpg`, `.webp`, `.mp4`, or `.webm` artifacts in `.local/showcase/evidence/`; they appear separately from the live adb source.

Run the focused persistence and bounds tests without touching a running showcase:

```powershell
python -m unittest tools/showcase/test_server.py -v
```
