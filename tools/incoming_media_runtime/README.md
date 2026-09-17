# Native incoming-media review and playback gate

This runner exercises the **normal installed Android app**, not a Flutter integration-test entrypoint. It reproduces the cold-start boundary where `FlutterFragmentActivity` may configure the engine after `MainActivity.onCreate` returns.

Use a dedicated Android emulator with the normal MeowWatch APK installed. The runner explicitly force-stops this package before each cold case, verifies that no app process exists, then delivers an Android intent directly to the exported production activity. It can finish first-run onboarding using the default local profile. After the cancellation cases, two additional cases press **Open video** and the production **Play** action. Invitations remain review-only; **Join this room** is not pressed.

```sh
python3 -m tools.android_native_ui.build
python3 -m tools.incoming_media_runtime.run \
  --serial emulator-5554 \
  --apk build/app/outputs/flutter-apk/app-release.apk
```

`--apk` records the supplied file's hash only; it neither installs nor proves that this file matches the installed package. The host workflow should install that exact APK first and retain installation evidence. Output goes to an initially empty `build/incoming-media-runtime-artifacts` directory by default.

Four media cases cover cold `ACTION_SEND`, warm `ACTION_SEND`, warm `ACTION_VIEW`, and cold `ACTION_VIEW`. Each uses a distinct fixed `https://example.invalid/...mp4` fixture. Three invitation cases cover cold/warm `meowwatch://join` VIEW delivery through `app_links` and a warm SEND text invitation through the media bridge. Each invitation has its own room and an explicitly reviewed server/port; no join command is issued. The runner requires:

- an actually absent process immediately before cold launch;
- the same application process before and after each warm intent;
- the production **Open shared video?** dialog with the exact expected filename and both Cancel/Open actions;
- the dialog remaining present until an explicit choice;
- Cancel dismissing the dialog without another copy appearing;
- invitation review showing the exact room, server and explicit Join action, with Android Back dismissing it without a duplicate;
- valid native screenshots, native accessibility XML, actual emulator model/API/ABI and installed package metadata.

The runner refuses physical-device serials and does not clear application data or reinstall the production application. It installs the separately built native UI observer into its own package and removes only that owned helper during cleanup. The observer never instruments the production application. Do not use an emulator that another task is actively operating.

The two confirmation cases use only the fixed public [Sintel trailer hosted by W3C](https://media.w3.org/2010/05/sintel/trailer.mp4). It is a 52.208333-second H.264 video, 854×480, with SHA-256 `b670602fa00934ca27c4351bb0efe7ea7a07fae57284e44226025eeed7c51254`. Downloads are capped at 8 MiB and changed bytes or redirects fail. No arbitrary URL or private media is accepted.

- HTTPS **Share** sends this exact URL to the normal activity, keeps its review visible until an explicit **Open video**, then presses **Play**.
- Content-provider **Open** creates a uniquely named Android MediaStore video row, writes the pinned fixture through the provider and verifies its readback hash. The VIEW intent requests temporary read access. The gate independently queries Android's URI permissions and requires the exact URI to have an activity-owned, non-persisted, read-only grant to MeowWatch before confirming Open. The production temporary-access warning must also be visible.
- Both cases require the actual source title, 52-second native duration, a player timeline and enabled playback controls. Fresh native observer snapshots must show playing time advancing by at least two displayed seconds in the same production process. Screenshots and XML capture both observations; a review label or Play icon alone cannot pass.

`confirmedPlayback` in `result.json` contains the source hash, provider readback hash, exact-URI hash, observed grant flags and playback samples. `confirmed-observations.json` retains the observer's nonce, Android uptime and process evidence. The cleanup record confirms deletion of only the previously verified exact MediaStore row. If ownership or deletion cannot be confirmed, the row is retained and explicitly reported; cleanup never deletes a collection or matches other names.

The gate does not prove network-request absence before confirmation, activity recreation, early warm-intent ordering while the engine is unavailable, or a completed invitation join. Those boundaries remain separate.

Native execution status of the new confirmation/playback cases: **not yet run**. Passing Python tests only checks the runner's command/UI assertions; it must not be recorded as Android acceptance. `confirmed-result.json` retains completed playback cases even if a later case fails.

```sh
python3 -m unittest tools.incoming_media_runtime.test_run tools.incoming_media_runtime.test_confirmed -v
```
