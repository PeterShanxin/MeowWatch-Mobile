# Native Android accessibility observer

This independent, test-only APK reads the active Android accessibility hierarchy
without waiting for the screen to become idle. It has no Activity, network or
storage permissions, and no application-private integration. Its instrumentation
targets **`com.meowwatch.native_ui_observer` itself**, never MeowWatch. Starting a
snapshot must preserve the foreground app's PID and leave its playback running.

Android's command-line `uiautomator dump` calls
[`waitForIdle(1000, 10000)`](https://android.googlesource.com/platform/frameworks/uiautomator/+/refs/heads/main/cmds/uiautomator/src/com/android/commands/uiautomator/DumpCommand.java).
A playing timeline can update accessibility values every 100 ms, so extending
the host timeout does not remove that one-second quiet-window requirement. This
helper instead uses the official
[`UiAutomation.getRootInActiveWindow`](https://developer.android.com/reference/android/app/UiAutomation#getRootInActiveWindow())
API directly, refreshes the root, and serializes ordinary `AccessibilityNodeInfo`
attributes. View-ID reporting is enabled for strict native system-dialog checks;
non-important nodes are excluded, matching the previous compressed hierarchy.
Invisible children are skipped like UIAutomator's dumper; an invisible root
fails capture. The host also rejects any invisible node in the returned tree.

## Build

Use an already installed JDK and official Android SDK. No Gradle project,
third-party dependency, Flutter test application or global configuration is needed.

```sh
python3 -m tools.android_native_ui.build --platform 35 --build-tools 36.0.0
python3 -m unittest tools.android_native_ui.test_observer -v
```

`ANDROID_HOME`/`ANDROID_SDK_ROOT` and `JAVA_HOME` select the tools; `--sdk` and
`--java-home` provide explicit paths. The output directory must start empty.
The build runs `javac`, D8, `aapt2`, `zipalign`, `keytool` and `apksigner` from
those installations. It verifies the APK signature and packaged instrumentation
target. `build/android-native-ui/build.json` records source/APK hashes and every
build-step exit status. The generated test signing key stays under ignored
`build/`; do not publish it. The helper is not part of the product APK.

## Capture contract

`NativeUiObserver` installs only on an explicit `emulator-*` serial whose
`ro.kernel.qemu` value is `1`, refuses a pre-existing helper package, verifies the
installed instrumentation target, and uninstalls only its own helper on cleanup.
The caller remains responsible for validating exact foreground-window focus.

The helper uses explicit `adb install --no-incremental -t`: the signing tool
creates an `.apk.idsig` sidecar, which otherwise lets ADB select incremental
delivery. Incremental success can have a timing line after `Success`; a completed
ordinary install is required before inspecting instrumentation. Exit status,
strict terminal `Success` and the installed self-target are all checked.
Installation diagnostics retain only recognized modes/status/error codes,
byte counts and output hashes, never raw installer payloads or paths.
The installed component check matches Android PackageManager's shortened
`package/.SnapshotInstrumentation` output and requires the exact self-target.
Missing, duplicate, additional or differently targeted instrumentation fails.

Each `am instrument -w -r` request carries a new random 128-bit nonce. Protocol 2
returns one XML snapshot as Base64 in its instrumentation result, together with
the nonce, device uptime, node count and bounded capture-attempt diagnostics.
Failed responses must also carry the matching nonce and a fresh device timestamp;
old protocol responses fail validation, so rebuild the helper when updating the
host. There is no shared
snapshot file to become stale. The host validates every field and requires
increasing device timestamps. It independently queries window focus and checks
the MeowWatch PID before and after capture. A PID change, malformed response or
stale nonce is fatal, including across timeout recovery.

The Java serializer and Python parser both enforce limits: 2,048 nodes, depth 48,
4,096 characters per attribute and 256 KiB of UTF-8 XML. The response is bounded
to 360,000 bytes. Missing roots, partial trees, malformed data and exceeded
limits fail instead of silently truncating or reusing a previous snapshot.
There is no UI-idle wait, input action or app lifecycle operation in the helper.
Errors expose fixed descriptions, never raw command/response payloads. Native
failure codes distinguish missing roots, failed refreshes, invisible roots,
missing children, structural limits and recognized exception categories. An
unknown exception is an immediate integrity failure; its message is never emitted.

Android can temporarily return a missing root or child while a new accessibility
connection or updated tree is being published. For these four transient reasons,
the helper permits at most four attempts in the **same** `UiAutomation` connection,
100 ms apart, under a four-second capture budget checked during traversal. Each
attempt obtains and refreshes a new active root, resets its node count and XML
buffer, and recycles the entire previous traversal. It never returns partial XML.
The ten-second host watchdog still bounds a blocked Android framework call.
Exceeding the internal time budget produces `capture_deadline`; structural limits
and native exceptions are never retried inside the connection or by callers that
honor `ObserverIntegrityFailure`. No acceptance deadline or timeline requirement
is extended.

`observer_attempts` is a bounded, content-free sequence of
`reason:visitedNodes:depth:childIndex:childCount` records. Unknown numeric locations
are `-1`; an excessive child count is capped at 2,049 for diagnostics only and
still fails capture. The host validates reason codes, numeric bounds, attempt
count and terminal success/failure consistency before retaining any diagnostics.
Only transient failures may precede another attempt. A successful final tree
must independently satisfy the existing node-count and XML checks.

Each capture has a ten-second instrumentation timeout. If it expires, the host
stops only the owned helper package, confirms that the app PID stayed unchanged,
and lets the caller retry within its original deadline. `observations` now records
both `status: success` and `status: failure`. Successful evidence retains the
nonce, device and host timestamps, app PID, node count and XML hash. Failed
captures retain fixed failure codes, validated attempt diagnostics when available,
host timing, process IDs and window-focus evidence. Window evidence contains only
its byte count/hash, focused-window count and whether MeowWatch was focused;
raw window titles and arbitrary response payloads are not copied into diagnostics.
The caller must still validate the actual returned window before accepting UI.
This does not make the tree atomic: it is a bounded live accessibility read,
so callers must still validate related timeline, source, controls and focus.

The local tests establish parsing, freshness, process and ownership rules.
Compilation establishes Android API compatibility. A successful native lifecycle
workflow is still required to establish actual playback and HOME behavior.
