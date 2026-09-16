# Cast playback

MeowWatch Mobile includes an Android Google Cast sender for direct HTTPS MP4 video. The phone remains the room controller; the receiver fetches and plays the video independently. This implements the first Cast slice described in [Product Spec §7.3](PRODUCT_SPEC.md#73-cast--external-playback---p1-strong-stretch-goal).

**Status, 2026-09-16:** the sender and playback-target contracts are implemented, with 14 focused automated tests passing. Physical Android-to-Cast discovery, receiver playback, background controls and reconnection are **unverified**. No physical Cast receiver has been used for the acceptance matrix below. Follow [Delivery status](STATUS.md) for integrated build and application verification.

## Requirements and supported media

- An Android phone with working Google Play services and a Chromecast, Google TV/Android TV with Cast, or Cast-enabled TV.
- The phone and receiver must be on the same Wi-Fi network with device-to-device discovery available. Guest-network isolation can prevent discovery.
- Internet access from the receiver to a public video URL. The phone does not proxy the file or share its browser login with the TV.
- A direct `https:` URL with a DNS hostname and a path ending in `.mp4` (case-insensitive), served as playable MP4 video.

The current source check rejects HTTP, username/password URLs, **all query parameters and fragments**, IP literals, single-label hosts, `.local`, `.localhost`, `.internal` and `.home.arpa` hosts. Signed/tokenized links, sign-in cookies and custom authorization headers are unsupported. `file:` and Android `content:` sources cannot be cast. There is no temporary phone-hosted media server.

A matching filename is only a source-format check. It does not establish public reachability, MIME correctness, codec compatibility, DNS routing or redirect behavior. The receiver must successfully fetch and load the actual media. Protected streaming services, DRM, webpages, adaptive streams, queues, receiver subtitles and custom receivers are outside this slice. Use media that you are authorized to play and that the receiver can access without credentials.

Google documents receiver-specific codec limits in its [supported media guide](https://developers.google.com/cast/docs/media). A conservative test fixture is a public HTTPS MP4 using H.264 video and AAC audio; compatibility still requires receiver-device evidence.

## Choosing a screen and recovering

Open an eligible video on the phone, then choose Cast from the playback-target selector. Actual receiver selection uses the official Google/Android MediaRouter chooser. MeowWatch Nearby discovery and pairing are a separate desktop feature; they are not used to discover Cast receivers.

The application handoff contract is:

1. Capture the accepted phone source and position, then pause the phone while the candidate receiver connects.
2. Load the same video on the receiver at that position, initially paused. Accept the TV target only after a playable receiver state is reported.
3. Rebind playback synchronization to the receiver using the existing phone `SyncplayClient`. Preserve the room, username, participant identity and hosting-session identity. A screen change is not another free hosted Together Session.
4. If connection or loading fails before acceptance, close only that candidate and preserve the accepted phone session for recovery.
5. Returning to the phone is explicit. Pause a reachable receiver, restore the accepted source and last known position on the phone, and leave the phone paused until the user chooses Play. End the owned Cast session after the phone target is accepted.

Returning to the phone paused is an application acceptance requirement; the low-level Cast adapter's unit tests do not establish that the integrated handoff satisfies it. Record that result separately in the matrix below.

Receiver disconnection never silently starts playback on the phone. A suspended, lost or replaced receiver requires visible recovery. If disconnection cannot be confirmed, check the TV's own Cast controls before continuing. A failed return must remain visible instead of claiming that the TV stopped.

For unsupported sources or unavailable Cast, continue on **This phone**. **Nearby MeowWatch** is an alternative for a separately paired desktop. Neither fallback claims to cast local files or bypass protected streaming restrictions. Return to the phone before moving between a TV and a Nearby desktop.

## Playback and ownership contract

[`CastPlaybackTarget`](../lib/core/cast/cast_playback_target.dart) implements the same load/play/pause/seek/snapshot boundary as phone playback. It exposes receiver name and connection state; each accepted update contains position, duration, play state and buffering state together.

- `connect()` explicitly claims control of a receiver session. Constructing a target or observing global native events grants no control.
- `load()` sends `video/mp4`, a source identifier and the requested position with autoplay disabled. It waits for command acknowledgment and a matching playable receiver state.
- Play, pause and seek await the receiver command result. They do not optimistically report success or playback changes.
- A finished item maps to ready/paused at its duration. Receiver errors map to failed playback. Session loss preserves the last known position and reports disconnected.
- A different sender replacing the media is not treated as the previously accepted MeowWatch video.
- Commands and their completion callbacks require both the current native session generation and the current owner token. Transferring ownership invalidates old controls even when the native Cast session itself remains the same.
- Closing an unconnected candidate cannot stop an existing TV session. Closing a retired owner cannot stop its replacement. Close is idempotent, and native disconnection is acknowledged through session termination or reports a bounded timeout.
- All Dart targets share one native event-channel subscription. Retiring an old target does not remove the new target's event handler.

The native bridge pins `com.google.android.gms:play-services-cast-framework:22.3.1` and uses Google's Default Media Receiver. The framework supplies the chooser, media notification, lock-screen actions and session reconnection mechanisms. Notification actions use the framework defaults; tapping the notification returns to MeowWatch. These are configured integrations, **not verified hardware behavior**. See the [official Android sender guide](https://developers.google.com/cast/docs/android_sender/integrate) and [feasibility decision](CAST_FEASIBILITY.md).

No room password, Syncplay token or Nearby pairing credential is sent as Cast metadata. The selected media URL necessarily goes to the receiver so it can fetch the video. Bridge status events and public errors do not include the raw URL, and receiver notification metadata currently uses the generic title “MeowWatch video.”

## Automated evidence

On 2026-09-16, `flutter test --no-pub test/core/cast` passed **14 tests**: 13 playback-target tests plus a platform-channel subscription test. Scoped Dart analysis and formatting also passed.

The tests exercise source rejection, coherent status mapping, acknowledgment-before-success, failed commands, end-of-media behavior, session replacement, external media replacement, position clamping, ownership transfer and cleanup. The channel test uses Flutter's actual Method/EventChannel machinery with the test binary messenger: one native listen is retained while either target subscribes, retiring the first listener does not stop the second, and the last listener cancels the native subscription.

The test receiver is a controlled transport substitute. These tests do not run Google's native receiver, discover a Chromecast, prove TV decoding, exercise a real notification, or validate Cast network recovery. Android compilation and phone/TV acceptance are separate evidence.

## Physical-device acceptance matrix

Record the commit and APK hash, sender model and Android API, Google Play services version, receiver model and firmware, Wi-Fi topology, exact media fixture/encoding, test date and tester. Keep recordings and sanitized results outside version control when they contain personal device/network details. Record each row as passed, failed or blocked; do not infer a pass from an emulator or a Dart test.

Use one physical Android sender, one real Cast receiver and a second independent MeowWatch client for room cases. Observe the receiver screen and phone together. Repeat screen-transfer and transport-control cases at least three times, including initially paused and initially playing media.

| Case | Procedure | Required observation / evidence |
| --- | --- | --- |
| Discovery and chooser | Open Cast on the same Wi-Fi; select the real receiver; cancel once and reopen. | Standard chooser lists the actual receiver. Cancellation clears waiting state. Reopening works without a second pending connection. |
| Initial load | Cast an eligible MP4 from both paused and playing phone states at a nonzero position. | Receiver loads the same source and position; the phone does not continue playing duplicate audio. Capture actual receiver picture and position. |
| Local controls | In Local Mode, play, pause, seek forward and backward on the phone. | TV follows every command; phone position and play state follow receiver feedback. A rejected command remains visible. |
| Room controls | With a second independent room client, issue play/pause/seek from each client. | Receiver and peer converge without repeated correction loops. Record measured position differences and convergence time; confirm the roster still has exactly the original participants. |
| Receiver-originated changes | Use the TV remote or another Cast sender to pause, resume and seek. Then replace the media from the other sender. | MeowWatch reflects remote controls; replacement media is never reported or synchronized as the previous source. |
| Buffering and failure | Interrupt receiver connectivity briefly; try an unavailable or incompatible public MP4 fixture. | Buffering/error is visible, commands do not falsely succeed, and retry or explicit return remains usable. Record which fault was actually induced. |
| Natural end | Play through the end of a short MP4. | Phone shows paused/ready at duration without restarting either screen unexpectedly. |
| Background controls | Background the app, use notification play/pause and stop, lock/unlock the phone, then return. | Notification/lock-screen controls affect the actual TV, and foreground state matches it. Record both sender and receiver behavior. |
| Network recovery | Remove and restore Wi-Fi during playback; repeat while the phone is backgrounded. | Suspension/loss is visible. Recovery either restores the valid receiver session or offers explicit recovery; no silent phone autoplay or stale controls. |
| Return to phone | From playing and paused TV states, choose Return to phone; repeat after receiver loss. | Accepted source and last known position are restored; **phone remains paused until Play**. Reachable TV is paused and its owned session ends; uncertainty is surfaced. |
| Room and quota continuity | Record roster, room identity and free-host usage before Cast, while casting and after return. | One phone participant remains; no ghost join, room replacement or extra hosted-session charge occurs. |
| Lifecycle and ownership | Recreate/reopen the Android activity; cancel a candidate, switch control to a new target and retire the old target. | Restored chooser does not crash. Old commands and cleanup cannot stop the new owner; new status continues arriving. No receiver resumes unexpectedly. |

Do not describe Cast as hardware-validated or feature this path as a stable submission demonstration until the applicable rows have fresh passing evidence. A missing receiver is a hardware-validation blocker; the implemented sender and phone fallback remain distinct deliverables.
