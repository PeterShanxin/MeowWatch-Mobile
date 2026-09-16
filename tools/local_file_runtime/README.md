# Local-file relaunch runtime gate

This gate verifies Android Storage Access Framework behavior that widget tests
cannot establish. It generates a reviewed CC0 video fixture, pushes it into the
emulator's public Download directory, opens the production
`ACTION_OPEN_DOCUMENT` picker, selects the exact visible filename through
UIAutomator, and lets MeowWatch receive the real `content:` URI.

Stage 1 uses the production media sheet, `MediaPicker`, `AppController`,
`LocalMobileTarget`, Android video decoder and `AppRepository`. It plays, pauses,
seeks, and persists Continue Watching state. The runner then verifies the app
package remains installed, force-stops the exact package process, and does not
clear app data or uninstall it.

Stage 2 starts another `flutter drive` process against the same APK using
`--keep-app-running`. Flutter's replacement install preserves application data.
The test opens the saved Continue Watching entry, so successful decode proves
both repository durability and the persisted Android URI grant from
`takePersistableUriPermission`.

Native screen recordings cover both processes. Native screenshots cover the
focused DocumentsUI selection and final app state; Flutter screenshots cover
the rendered player. Results contain only the fixture filename, booleans,
durations, positions, process IDs and emulator metadata. Content URI values and
credential-like evidence keys are rejected, and Flutter drive logs redact any
unexpected `content:` URI.

This is API 35 x86_64 emulator evidence. It does not prove behavior for every
document provider, OEM picker, codec or physical device.

The workflow invokes the runner from the repository root as a module:

```sh
python3 -m tools.local_file_runtime.run \
  --serial emulator-5554 \
  --apk build/app/outputs/flutter-apk/app-debug.apk \
  --fixture build/local-file-runtime-fixture/sync-fixture.mp4
```
