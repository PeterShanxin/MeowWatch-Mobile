# Google Cast feasibility

Research date: 2026-09-16

## Decision

Google Cast is technically feasible for the Android sender in this repository. It is a **go after the P0 playback and Nearby paths are stable**, with a deliberately narrow first slice:

- Android sender only;
- Google's Default Media Receiver;
- public, receiver-accessible HTTPS MP4 media only;
- connect through the standard Cast/MediaRouter chooser;
- load, play, pause, seek, disconnect and coherent remote status;
- the phone remains the Syncplay participant and room controller.

The first slice should not include local files, phone-hosted HTTP, DRM, authenticated streaming services, queues, subtitles, a custom receiver, or Android's Output Switcher. Those are separate features with different hosting, lifecycle and compliance requirements.

Lack of a physical sender and Cast receiver is a validation blocker, not an implementation blocker. Unit tests and an Android build can prove the bridge contract, but they cannot prove multicast discovery, receiver launch, media compatibility, TV playback, background controls or reconnection.

## Why the current app can support it

The product requirement is compatible with the existing architecture:

- `PlaybackTarget` already defines the required `load`, `play`, `pause`, `seek`, state stream and coherent `PlaybackSnapshot` boundary.
- `PlaybackSyncBridge` already consumes a `PlaybackTarget`, so receiver position and play state can feed the existing synchronization logic without creating another Syncplay participant.
- `MediaItem.fromUrl` already distinguishes direct HTTP(S) media from local `content:` and `file:` sources.
- Android `MainActivity` already extends `FlutterFragmentActivity`, which is compatible with the Cast Application Framework's `FragmentActivity` integration.
- Flutter 3.44 currently gives this project Android min SDK 24, compile/target SDK 36. Google's current Android sender guide requires min SDK 24 and targets API 35, so the project is not below the SDK floor.

There are two integration gaps that must be addressed explicitly:

1. `AppController.target` is currently fixed to either Nearby desktop or phone, and `PlaybackSyncBridge.target` is final. Switching phone to Cast inside an existing room therefore needs a controlled target handoff that rebuilds or rebinds the bridge while retaining the same `SyncplayClient`.
2. `RoomScreen` renders video only for `LocalMobileTarget` and otherwise has Nearby-specific copy. A Cast target needs a TV status surface and an official Cast connect/disconnect affordance.

The current Android manifest has general network permissions, but no Cast `OptionsProvider` metadata or Cast media notification configuration. Those are implementation work, not evidence that Cast is unavailable.

## Current Google platform requirements

The current official Android Sender SDK is `com.google.android.gms:play-services-cast-framework:22.3.1`. Google documents that the framework owns discovery, session recovery and receiver communication through `CastContext`; an `OptionsProvider` and its manifest metadata select the receiver application. `RemoteMediaClient` loads media and supplies command results and remote playback status. See the [Android sender integration guide](https://developers.google.com/cast/docs/android_sender/integrate), [Google Play services release notes](https://developers.google.com/android/guides/releases), and [RemoteMediaClient reference](https://developers.google.com/android/reference/com/google/android/gms/cast/framework/media/RemoteMediaClient).

The first implementation does not need a custom receiver. Google's [receiver overview](https://developers.google.com/cast/docs/web_receiver) and [registration guide](https://developers.google.com/cast/docs/registration) state that the Default Media Receiver uses the provided application ID and does not require application or receiver registration. A Styled or Custom Web Receiver would require a Cast Developer Console application ID; unpublished receiver development would also require registering each physical receiver device.

The receiver fetches the media independently from the phone. The URL must therefore be reachable by the receiver, and the supplied MIME type and codec must be supported. Google's [supported media guide](https://developers.google.com/cast/docs/media) includes MP4/H.264/AAC and documents device-specific codec limits. Adaptive streams and media with tracks add CORS requirements, including range-related headers; those are outside the first slice.

Google's UX guidance requires the standard Cast button/dialog behavior and background controls. The Android framework supplies the MediaRouter chooser, media notification and lock-screen controls. Discovery is lifecycle-managed by `CastContext`; it should not be replaced with MeowWatch's Nearby mDNS browser. See the [Cast button guidance](https://developers.google.com/cast/docs/design_checklist/cast-button), [Cast dialog guidance](https://developers.google.com/cast/docs/design_checklist/cast-dialog), and [Android sender integration guide](https://developers.google.com/cast/docs/android_sender/integrate).

Real discovery requires a suitable sender and an official Cast-capable receiver on the same Wi-Fi network. Google's [discovery troubleshooting guide](https://developers.google.com/cast/docs/discovery) uses that setup, and its [Android sender UI-test guide](https://developers.google.com/cast/docs/android_sender/automate_ui_tests) describes the connection test on a physical device. An emulator-only pass must not be reported as Cast-device evidence.

## API option assessment

| Option | Current evidence | Decision |
| --- | --- | --- |
| Official Android Cast Application Framework behind a small MeowWatch Method/EventChannel | Google-maintained SDK, current 22.3.1 release, standard MediaRouter UX, full `RemoteMediaClient` state and command results | **Recommended.** It keeps the production dependency and lifecycle contract explicit and fits the existing Android-only platform channel pattern. |
| [`flutter_chrome_cast` 1.4.8](https://pub.dev/packages/flutter_chrome_cast/versions) | Actively published, verified publisher, exposes discovery/session/media status and play/pause/seek. Its setup adds several Dart dependencies and native manifest/service behavior; its native guide still tells consumers to use `play-services-cast-framework:21.+` | Useful for an isolated comparison spike, but do not make it the production default until Flutter 3.44, AGP 9, SDK 22.3.1, official chooser UX, lifecycle and error propagation are verified on hardware. |
| [`flutter_cast_framework` 0.0.1-alpha.1](https://pub.dev/packages/flutter_cast_framework/versions) | Describes itself as a proof of concept; one alpha release four years ago from an unverified uploader | Reject for production. |
| [`googlecast` 1.0.0](https://pub.dev/packages/googlecast/versions) | Recently republished but explicitly audio-only, from an unverified uploader | Reject for MeowWatch video. |

The recommended bridge is not a reimplementation of the Cast protocol. Kotlin should call Google's framework and expose only the small Dart contract MeowWatch needs.

## Recommended first implementation slice

### Native Android boundary

1. Pin `play-services-cast-framework:22.3.1` rather than a dynamic version.
2. Add a `CastOptionsProvider` using `CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID` and configure the framework-provided notification/lock-screen controls.
3. Add an official `MediaRouteButton`/MediaRouter chooser entry to the existing playback-target UI. Do not present MeowWatch's own list as if it were the Cast chooser.
4. Implement one MethodChannel and one EventChannel for:
   - current session and receiver display name;
   - session connecting/connected/suspended/disconnected/failed;
   - media loading/ready/buffering/playing/paused/idle/failed;
   - position and duration updates;
   - `load(url, contentType, title, positionMs, autoplay)`, `play`, `pause`, `seek` and `disconnect`.
5. Await Cast `PendingResult` completion and return stable public error codes. Session generation checks must discard callbacks and command completions from a superseded receiver session.

No room password, Nearby credential, device secret or Syncplay token belongs in Cast metadata. A media URL is sent to the receiver because the receiver must fetch it; it must not be logged, and URL query parameters must not appear in diagnostic events.

### Dart playback boundary

Create `CastPlaybackTarget extends PlaybackTarget`. It should:

- accept only `https:` network media in the first slice;
- initially support an unambiguous `video/mp4` source contract;
- publish one coherent `PlaybackSnapshot` per native status update;
- map an ended receiver item to ready/paused at duration, and session loss to disconnected rather than silently resuming the phone;
- issue no optimistic state changes before native acknowledgment;
- close subscriptions and the owned Cast session idempotently.

### Target handoff

Add an explicit AppController handoff instead of assigning a field:

1. capture the accepted phone media, position and play state;
2. pause the phone and invalidate stale media operations;
3. connect the user-selected Cast receiver through the official chooser;
4. load the same direct HTTPS media at the captured position;
5. only after the receiver confirms a playable media session, switch the active target;
6. dispose and recreate the `PlaybackSyncBridge` against the same live `SyncplayClient`, then confirm the already-open source;
7. preserve quota/session identity and keep exactly one Syncplay participant;
8. on failure, close the candidate Cast target and leave the accepted phone target and bridge intact.

Returning to phone should use the last receiver position, pause the receiver before transfer, load/seek the phone target, rebuild the bridge, and only then end the Cast session. A disconnected receiver should show a recovery choice; it must not automatically start local audio or video.

### UI

- Keep phone, Nearby desktop and Cast within the same device chooser, but use the standard Cast chooser for actual receiver selection.
- While casting, replace the local video surface with receiver name, connection/buffering state, media title and a clear “Playing on TV” indication.
- Keep the existing play/pause/seek controls backed by `PlaybackTarget`.
- Keep Cast visible anywhere playable content is visible, following Google's Cast button guidance.
- Local files and `content:` URIs should explain that the first Cast version needs a direct HTTPS MP4 link; do not start a hidden local HTTP server.

## Validation gate

Automated tests should cover snapshot mapping, command acknowledgment, stale-session callbacks, handoff rollback, bridge rebinding, no duplicate Syncplay participant, disconnect behavior and URL redaction. An Android debug/release build must also pass.

Completion still requires a physical Android sender and a real Chromecast, Google TV/Android TV with Cast, or Cast-enabled TV on the same non-isolated Wi-Fi network. Record the actual sender model/API and receiver model. Verify:

1. official chooser discovery, connection and disconnect;
2. direct HTTPS MP4 load from stopped and already-playing phone states;
3. play, pause and seek in both local and synchronized rooms;
4. position/play-state updates originating from the TV remote or another Cast sender;
5. receiver buffering/error/ended status mapping;
6. app background/foreground, notification and lock-screen controls;
7. Wi-Fi interruption and Cast session reconnection;
8. transfer back to phone without duplicate audio, duplicate Syncplay users, quota recounting or silent autoplay.

Until that gate is run, the accurate status is: **sender implementation feasible; receiver-device behavior unverified because physical Cast hardware evidence is absent.**
