# Native incoming-media review gate

This runner exercises the **normal installed Android app**, not a Flutter integration-test entrypoint. It reproduces the cold-start boundary where `FlutterFragmentActivity` may configure the engine after `MainActivity.onCreate` returns.

Use a dedicated Android emulator with the normal MeowWatch APK installed. The runner explicitly force-stops this package before each cold case, verifies that no app process exists, then delivers an Android intent directly to the exported production activity. It can finish first-run onboarding using the default local profile; it never presses **Open video**.

```sh
python3 -m tools.incoming_media_runtime.run \
  --serial emulator-5554 \
  --apk build/app/outputs/flutter-apk/app-release.apk
```

`--apk` records the supplied file's hash only; it neither installs nor proves that this file matches the installed package. The host workflow should install that exact APK first and retain installation evidence. Output goes to an initially empty `build/incoming-media-runtime-artifacts` directory by default.

The four cases are cold `ACTION_SEND`, warm `ACTION_SEND`, warm `ACTION_VIEW`, and cold `ACTION_VIEW`. Each uses a distinct fixed `https://example.invalid/...mp4` fixture. The runner requires:

- an actually absent process immediately before cold launch;
- the same application process before and after each warm intent;
- the production **Open shared video?** dialog with the exact expected filename and both Cancel/Open actions;
- the dialog remaining present until an explicit choice;
- Cancel dismissing the dialog without another copy appearing;
- valid native screenshots, native accessibility XML, actual emulator model/API/ABI and installed package metadata.

The runner refuses physical-device serials and does not clear application data or install/uninstall packages. It stops the tested application and removes only its own remote evidence files when finished. Do not use an emulator that another task is actively operating.

The fixtures deliberately do not serve video. This gate proves real native intent delivery into a confirmation surface; it does **not** prove video playback, network-request absence, a content-provider read grant, activity recreation, or early warm-intent ordering while the engine is still unavailable. The separate Dart tests cover confirmation-independent parsing, temporary-grant metadata and queue races. Content-provider access and recreation need their own native evidence.

Native execution status: **not run when this gate was added**. Passing Python tests only checks the runner's command/UI assertions; it must not be recorded as Android acceptance.

```sh
python3 -m unittest tools.incoming_media_runtime.test_run -v
```
