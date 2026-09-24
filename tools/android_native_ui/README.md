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
connection or updated tree is being published. For these transient reasons,
the helper permits at most four attempts in the **same** `UiAutomation` connection,
100 ms apart, under an eight-second capture budget checked during traversal. This
budget starts after UiAutomation and accessibility service configuration are
ready; cold instrumentation startup does not spend the hierarchy budget. Each
attempt obtains and refreshes a new active root, resets its node count and XML
buffer, and recycles the entire previous traversal. It never returns partial XML.
An independent host watchdog still bounds a blocked Android framework call.
Exceeding the internal time budget produces `capture_deadline`; structural limits
and native exceptions are never retried inside the connection or by callers that
honor `ObserverIntegrityFailure`. No acceptance deadline or timeline requirement
is extended.

An expected Flutter application's native containers can also appear before its
virtual accessibility descendants. In API 35 evidence, a review dialog remained
rendered while a new connection returned only two empty `FrameLayout` nodes.
The host sends `expectedPackage` with its verified application package. Only a
tree entirely in that package, entirely composed of `android.widget.FrameLayout`
nodes, with no text, description, resource ID, click/long-click, scroll or check
action is classified as `flutter_semantics_unavailable`. The helper discards it
and rereads a fresh root in the same connection under the existing attempt and
time budgets. The host independently rejects an empty shell incorrectly marked
successful. A different package, a real control or any accessible content does
not meet this condition, even in a one-node tree. Such a complete tree still
faces the caller's original review and playback assertions immediately; a wrong
or dismissed review is never repaired by waiting for the expected title.

`observer_attempts` is a bounded, content-free sequence of
`reason:visitedNodes:depth:childIndex:childCount` records. Unknown numeric locations
are `-1`; an excessive child count is capped at 2,049 for diagnostics only and
still fails capture. The host validates reason codes, numeric bounds, attempt
count and terminal success/failure consistency before retaining any diagnostics.
Only transient failures may precede another attempt. A successful final tree
must independently satisfy the existing node-count and XML checks.

The host streams bounded output from its own adb child. It allows at most twenty
seconds from instrumentation dispatch to a validated `service_ready`, then eight
seconds of native hierarchy work and at most two seconds of result delivery.
The entire observation, including PID/window checks, has a thirty-second
absolute limit, capped by any earlier caller deadline. The service-ready marker
must follow the exact startup sequence with the same fresh nonce and helper PID.
Repeated or foreign readiness cannot reset a deadline. A native traversal at or
beyond eight seconds is rejected even if response-delivery time remains. `finish`
can only shorten the remaining result deadline; it cannot grant more time.

An expired startup/capture/caller budget is terminal: the host reaps only its own
adb process, stops only the owned helper package when instrumentation is active,
and confirms that the app PID stayed unchanged. It never retries a cold start to
replace an expired budget. Cleanup may finish after the acceptance deadline but
cannot earn phase credit. Lifecycle callers pass their original absolute deadline
and reject late results before and after their UI predicate. `observations` records
both `status: success` and `status: failure`. Successful evidence retains the
nonce, device and host timestamps, app PID, node count and XML hash. Failed
captures retain fixed failure codes, validated attempt diagnostics when available,
host timing, process IDs and window-focus evidence. Window evidence contains only
its byte count/hash, focused-window count and whether MeowWatch was focused;
raw window titles and arbitrary response payloads are not copied into diagnostics.
The caller must still validate the actual returned window before accepting UI.
This does not make the tree atomic: it is a bounded live accessibility read,
so callers must still validate related timeline, source, controls and focus.

## Stage timing diagnostics

Each request emits at most 40 fixed stage records to the `MWNativeUiStage` Logcat
tag and to instrumentation progress status code `2`. Records contain only
`nonce:helperPid:sequence:stage:uptimeMs:attempt:visitedNodes`. The stages identify
`on_create`, `on_start`, UiAutomation connection start/readiness, service readiness,
each root read, root refresh, traversal, failed attempt and `finish`. There are no
per-node log messages, UI strings, window titles, resource IDs or exception text.
The sequence and native uptime distinguish cold process startup, connection
setup and actual hierarchy work. An absent stage does not establish which later
operation would have succeeded.

Python accepts only complete progress records with the current nonce, one
positive helper PID, consecutive sequence numbers, nondecreasing uptime, known
stages and bounded attempt/node counts. `instrumentationProgress` records these
stages plus output byte count and SHA-256 on success and failure. On the unchanged
startup/capture timeout it retains the validated prefix available in
`TimeoutExpired.output`, then stops only the helper. Incomplete or
malformed trailing diagnostics are classified with fixed codes. Arbitrary
partial XML and stderr text are never copied into diagnostics; stderr retains
only the same bounded metadata. Logcat independently retains stages emitted
before a watcher disappeared. No extra ADB observation or retry is added.

Progress alone never satisfies capture. The final Protocol 2 response must still
pass all nonce, freshness, complete hierarchy, attribute and structural checks;
malformed progress also rejects a completed response. The 360,000-byte response
limit still accommodates the maximum 256 KiB XML plus all 40 stage records.
The eight-second hierarchy budget, four attempts and 100 ms retry interval are
bounded by any earlier caller deadline. Startup has its separate bounded
allowance; no previous/partial tree may replace a failed capture. The twenty-second
startup setting addresses observed API 35 cold connection delays, not a guarantee
under arbitrary system load. The full helper still needs fresh native acceptance.

The capture budget was raised from four to eight seconds after network run
`35960629684`: the second root took 678 ms to fetch, followed by refresh and
3.388 seconds of traversal before stopping at node 28, 4.397 seconds after service
readiness. The app stayed alive and playing, but no complete tree was accepted.
This is a test-tool latency allowance, not an app performance fix. It permits a
longer sampling span and slower failure detection; it does not make the XML an
atomic snapshot, relax playback/synchronization assertions, reuse partial trees
or extend a caller's absolute deadline. The default Android prefetch strategy is
unchanged because the available evidence does not establish a cache/IPC cause.

The local tests establish parsing, freshness, process and ownership rules.
Compilation establishes Android API compatibility. A successful native lifecycle
workflow is still required to establish actual playback and HOME behavior.
