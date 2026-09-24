# Portable Syncplay core

## Provenance

The protocol, framing, room/share-code helpers, follow policy, watchdog,
chat signals/history and associated regression tests are adapted from
[PeterShanxin/MeowWatch](https://github.com/PeterShanxin/MeowWatch/tree/c7cc4be5203abe28fb1cd043c286367fd1e3ba46)
at commit `c7cc4be5203abe28fb1cd043c286367fd1e3ba46`, under **AGPL-3.0-only**.
The remote `main` SHA was verified on 2026-09-16. Source was read using
`git show`; the desktop checkout and its unrelated changes were not modified.

Mobile adaptations:

- `lib/core/sync`, `lib/core/connect`, and `lib/core/chat` use Dart IO and
  `meta`, without Flutter widgets, desktop playback, logging, or database imports.
- `EndpointSettings` replaces the desktop settings database dependency.
  `RoomConfig` contains only room connection identity and discovery policy.
- Cancelling/disposal now resolves a pending `connectUntilJoin`, instead of
  leaving the caller waiting after its transport has been torn down.
- `lib/core/session/playback_sync_bridge.dart` adapts desktop source-confirmation
  and no-echo rules to the mobile `PlaybackTarget` contract. Native commands
  have source/intent generation checks, serialized application, bounded waits,
  and a cancellable authorization wait before local or remote play.
- The loopback fixture relays chat and sends ordinary State acknowledgements
  on its heartbeat, avoiding an artificial unbounded reply-to-reply loop.

## Integration contract

Subscribe before connecting: all streams are broadcast. `SyncCore` exposes:

| Surface | Purpose |
|---|---|
| `connectionState`, `lastConnectionState` | Connection transitions and snapshot |
| `peerState`, `lastObservedRoomState`, `lastObservedRoomStateAge` | Playback commands, newest observed room state and its monotonic receive age |
| `presence`, `initialRoster`, `peerFile` | Membership, initial room members, announced media |
| `chat`, `activity` | Room messages and playback activity |
| `updateLocalState`, `notifyLocalChange` | Heartbeat cache and explicit user change |
| `announceFile`, `sendChat`, `disconnect`, `dispose` | Session commands and teardown |

`SyncplayClient.connectUntilJoin(...)` resolves to `null` on a completed secure
join or an actionable error string. It accepts an optional asynchronous
`onHandoff`, keeping its error listener active during a UI handoff.
Discovery performs real joins sequentially, disposes unsuccessful clients,
skips unreachable or insecure endpoints, and stops on a post-Hello room refusal.
Share the *successful* endpoint using `encodeShareCode`. Join codes pin that
endpoint; independently scanning a friend's room can create a different room.

`ChatStore` exposes immutable `messages` and `stream`, plus `reactions`,
`typing`, and `leaving` streams. `send`, `sendReaction`, and `sendTyping`
delegate to the protocol; visible chat is inserted only after the server echo.
UI owns typing expiry and room-specific presence text.

`PlaybackSyncBridge` owns neither the target nor the client. Call `start()`
before joining, and `dispose()` before replacing/closing its target. Use
`load(media, position: ...)` for a new source. A controller that owns loading
can instead call `beginSourceLoad()` and pass the returned generation to
`markSourceOpen(uri, generation: ...)` only after accepting the load.
`adoptOpenSource(uri)` handles a source already open before switching from
Local to Together.

After an accepted first Play, the bridge checks startup lag only once the native
position advances beyond the accepted seek. It projects from a room heartbeat
no older than two seconds, including heartbeats that did not issue a follow
command; the original Play plus elapsed wall time can overshoot a peer that also
buffered. A startup correction requires at least 750 ms of lag and never seeks
to EOF. Since the corrective seek can itself buffer, the watch remains until
native playback advances again, with at most two corrections in twelve seconds.
An initially aligned sample or temporarily stale heartbeat also keeps this
bounded watch, so subsequent startup buffering can still be corrected.
Pause, explicit seek, connection loss, source replacement and disposal cancel
this watch. Corrections update the ordinary heartbeat without publishing a new
user seek. The existing one-directional four-second steady-state rewind policy
is unchanged.

All synchronized user controls go through `play()`, `pause()` and `seek()`.
Player events update the cached heartbeat; they never infer or echo user
intent. Incoming room state is acknowledged synchronously before asynchronous
native commands. The bridge applies the most recent room snapshot after a
slow load and prevents superseded commands from issuing a later play.
The target must also isolate outstanding native work when replacing its source.
The session controller calls `peerLeft()` when the last peer leaves;
connection loss triggers this pause automatically. A reconnect reannounces the
confirmed source, and does not itself issue a Play command.

The mandatory `authorizePlayback` callback lets the controller apply hosting
quota to actual playback, including play initiated by a remote peer. Return
true for eligible guests and already authorized sessions. A denied play stays
paused and publishes that paused state. A new pause, load, or disposal cancels
the bridge's wait for an outstanding authorization response. Report `onError`
to the user; native playback failures must not silently disappear.

## Verification

On 2026-09-16, using Flutter 3.44.0 / Dart 3.12.0 on Windows:

- **373 tests passed** across protocol/connect/chat and the mobile bridge.
  Coverage includes malformed/refused/failed STARTTLS with no plaintext Hello,
  endpoint failure fallback, reconnection/watchdog, room identity, framing,
  chat ownership/retention, source races, authorization cancellation, and two
  real socket clients driving two in-memory playback targets in both directions.
- Scoped analyzer: **No issues found**. The host's default Dart performance
  socket directory returned Windows error 1920; using a process-local
  `LOCALAPPDATA` under the task's temporary directory avoided this without
  changing or deleting the shared directory.
- Two live smoke runs completed against **syncplay.pl:8995** using production
  `SecureSocket.secure`, certificate and hostname verification. Both proved
  bidirectional play/pause/seek, chat, reactions, and typing. The second also
  proved initial roster, peer presence, and a new secure connection after
  forced teardown of a real live socket through the watchdog recovery path.

Reproduce the offline checks:

```powershell
& "$env:USERPROFILE\.puro\envs\stable\flutter\bin\flutter.bat" test --no-pub test/core/sync test/core/connect test/core/chat test/core/session/playback_sync_bridge_test.dart
```

Explicit live network check (creates one short-lived random room, then closes
both clients; it is deliberately separate from the offline test suite):

```powershell
& "$env:USERPROFILE\.puro\envs\stable\flutter\bin\dart.bat" run test/support/syncplay_live_smoke.dart
```

The loopback fixture bypasses TLS via a test-only attachment hook; dedicated
fail-closed tests and the live public check cover real transport separately.
These results prove the portable protocol and target boundary. They do **not**
prove Android decoding, physical audio/video convergence, radio/network loss,
background lifecycle, mobile-to-desktop playback, or a RevenueCat purchase.
Those require integrated device evidence.
