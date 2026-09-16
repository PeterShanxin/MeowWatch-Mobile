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

The DocumentsUI search selector matches `search_src_text` in the focused system
picker and accepts its `AutoCompleteTextView` accessibility class, as well as
`EditText`. Android's [SearchView search field](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/master/core/java/android/widget/SearchView.java)
inherits `AutoCompleteTextView`, whose [API 35 accessibility class](https://android.googlesource.com/platform/prebuilts/fullsdk/sources/+/refs/heads/main/android-35/android/widget/AutoCompleteTextView.java)
is distinct from `EditText`.

`native/documentsui-selector.json` retains the last selector phase, search-control
class/flags and completion status; it never includes query text or URI values.
A selector failure stops the runner-owned Flutter drive process immediately,
instead of being masked by its longer wall timeout. Successful selection still
requires the exact fixture in focused DocumentsUI and the app regaining focus.

This is API 35 x86_64 emulator evidence. It does not prove behavior for every
document provider, OEM picker, codec or physical device.

The workflow invokes the runner from the repository root as a module:

```sh
python3 -m tools.local_file_runtime.run \
  --serial emulator-5554 \
  --apk build/app/outputs/flutter-apk/app-debug.apk \
  --fixture build/local-file-runtime-fixture/sync-fixture.mp4
```
