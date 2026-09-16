# Nearby MeowWatch protocol, version 1

**Status: companion application server/client and platform adapters implemented.
Native Android TLS, storage and NSD and Windows storage/player checks pass;
physical phone-to-desktop LAN acceptance remains pending.**
Prepared 2026-09-16 against Product Spec sections 7.1–7.2 and 15. Desktop reference:
`PeterShanxin/MeowWatch` main `c7cc4be5203abe28fb1cd043c286367fd1e3ba46`, verified
against the remote. Its AGENTS.md and full AGENT_GUIDE.md were read. The dirty
desktop checkout was inspected through `git show` and was not modified.

## Product and ownership boundary

The desktop is the player and the sole Syncplay participant while the phone
acts as its companion. The phone receives the desktop's room, roster, media,
chat and playback state and relays user actions. It must not put its own
`SyncplayClient` or `PlaybackSyncBridge` around `NearbyDesktopTarget`: that
would create a second room participant and two independent control loops.

The bridge starts disabled. Desktop settings expose **Nearby devices**, an
explicit pairing action, pending-device approval, paired-device removal, and
**Stop nearby control**. These are session controls, not an unauthenticated
background service installed with Windows. Closing the app closes its listener.

One paired phone controls at a time in v1. Additional devices may pair but
receive `controller_busy` until the current controller disconnects or the
desktop owner explicitly takes it over. Desktop keyboard/mouse controls always
remain available. The phone controls the existing desktop display name; it
does not add its device name to the Syncplay roster.

## Transport and network scope

Use length-bounded UTF-8 JSON objects terminated by LF over **TLS from byte
zero**, ALPN `meowwatch-companion/1`, minimum TLS 1.2. There is no HTTP, browser
control surface, plaintext mode, or STARTTLS negotiation here. The separate
public Syncplay client keeps its existing strict certificate validation.
Dart provides the required server socket and TLS-version controls.
([SecureServerSocket.bind](https://api.dart.dev/dart-io/SecureServerSocket/bind.html),
[minimum TLS version](https://api.dart.dev/dart-io/SecurityContext/minimumTlsProtocolVersion.html))

- Bind a selected **numeric address of an active LAN interface**, never
  `0.0.0.0` or `::`. The desktop displays the selected interface/address.
- Initially allow RFC1918 IPv4 and link-local IPv4; include IPv6 ULA/link-local
  only after scope-ID and prefix tests pass. Reject public, multicast,
  unspecified and loopback destinations in shipping mobile pairing.
- Check the accepted peer belongs to the selected adapter's on-link prefix;
  a private address alone does not prove it is on that LAN. Exclude tunnels
  and unrelated virtual adapters from automatic selection. Adapter/prefix
  changes close connections and refresh the listener/advertisement.
- Obtain Windows adapter addresses/prefix lengths through the existing native
  runner or a narrow platform adapter; `NetworkInterface.list` alone does not
  provide the prefix information required for this check.
  ([GetAdaptersAddresses](https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-getadaptersaddresses),
  [unicast address structure](https://learn.microsoft.com/en-us/windows/win32/api/iptypes/ns-iptypes-ip_adapter_unicast_address_lh))
- Document a Windows **Private-network, executable-specific, LocalSubnet**
  inbound firewall rule if needed. Never disable the firewall, add public
  exposure, forward router ports, or enable UPnP. Permission denial yields a
  clear connection error and setup guidance.
- LAN scoping limits exposure; a router/proxy can obscure source addresses.
  Encryption and explicit cryptographic pairing remain mandatory on every
  connection, including a trusted home network.

Resolve any discovered hostname once, validate the resulting numeric address,
and connect to that address. Revalidate on every new connection; do not allow
DNS rebinding to a public address or silently follow redirects.

## Discovery and identity

Advertise `_meowwatch._tcp` only while Nearby is enabled. TXT fields:
`v=1`, `id=<random persistent desktop ID>`, `pairing=0|1`, and a bounded
display name. Never advertise a room name, filename, token, secret or user
identity. Discovery is an **untrusted address hint**, not authentication.

The `nsd` package exposes Android discovery and Windows registration, including
TXT records and address resolution; its published platform support is a
candidate, not proof that the desktop build or LAN works. Keep discovery behind
an adapter and retain QR/full-invitation paste fallback when multicast fails.
([nsd documentation](https://pub.dev/packages/nsd),
[upstream implementation](https://github.com/sebastianhaberey/nsd))

On Android, handle permission denial as such rather than an empty device list.
The SDK 37+ local-network permission rules differ from SDK 36 and below; inspect
the actual target SDK at implementation time. For target 37+, evaluate the
system NSD picker or request the required local-network runtime permission;
older targets must not blindly request the new permission.
([Android local network guidance](https://developer.android.com/privacy-and-security/local-network-permission))

## Certificate provisioning and secret storage

Recommended first implementation: generate a self-signed RSA-2048 certificate
once when Nearby is enabled, in an isolate. `basic_utils` has RSA key generation,
CSR generation and self-signing APIs. Use SHA-256, a random positive serial,
server-auth usage, and a one-year lifetime. Feed PEM bytes to a private Dart
`SecurityContext` via `usePrivateKeyBytes` and `useCertificateChainBytes`; no
OpenSSL executable, administrator install or system trust-store mutation is
needed. The shared package's real Dart server/client TLS spike now passes on the
Windows ARM host with Dart 3.12.0. In `basic_utils` 5.8.2, omit the optional
`keyUsage` argument: its emitted BIT STRING contains nonzero unused bits and
BoringSSL rejects the certificate. Server-auth EKU and non-CA BasicConstraints
remain enabled. Set server ALPN on `SecurityContext.setAlpnProtocols(..., true)`;
the socket bind argument alone did not negotiate ALPN on the tested runtime.
([RSA key generation](https://pub.dev/documentation/basic_utils/latest/basic_utils/CryptoUtils/generateRSAKeyPair.html),
[self-signed certificates](https://pub.dev/documentation/basic_utils/latest/basic_utils/X509Utils/generateSelfSignedCertificate.html),
[Dart private key input](https://api.dart.dev/dart-io/SecurityContext/usePrivateKeyBytes.html))

Pin `SHA256(certificate.der)` to the desktop identity, using Dart's actual peer
certificate bytes. Check that pin after `SecureSocket.connect` completes even
if `onBadCertificate` did not run. Also enforce validity dates. Renewal/key
rotation requires explicit re-pairing in v1; never silently replace a stored
pin with mDNS data. ([Dart certificate DER](https://api.dart.dev/dart-io/X509Certificate/der.html),
[SecureSocket.connect](https://api.dart.dev/dart-io/SecureSocket/connect.html))

Persist desktop private key and device authorization secrets through
`flutter_secure_storage`, scoped separately from production when
`MEOWWATCH_DATA_DIR` is set. Store the phone's token and pin in platform secure
storage, not preferences/history JSON. The package supports Windows and Android;
its Windows ATL build prerequisite and Android backup exclusions must be tested
in the actual builds. Secure-storage failure stops pairing and control; there
is no plaintext or ephemeral-credential fallback. Never reuse the desktop
release-signing key for TLS or pairing.
([secure storage package](https://pub.dev/packages/flutter_secure_storage))

## Pairing ceremony

Opening **Pair a phone** creates one in-memory invitation with `pairId` (16
random bytes), `pairSecret` (**16 cryptographically random bytes**, 128 bits),
and a **120-second monotonic expiry**. Refresh/cancel invalidates the previous
invitation and pending approvals immediately. Restart invalidates invitations.

Default: display a QR payload containing protocol version, desktop ID, numeric
LAN address/port, certificate SHA-256, pair ID and pair secret. Use the dedicated
pairing payload defined in [NEARBY_WIRE.md](NEARBY_WIRE.md), distinct from public
room invites. The desktop displays a countdown alongside the QR.
The mobile scanner parses locally and never opens an external URL. Do not send
pairing payloads through analytics, logs or public link shorteners.

Manual fallback: **Copy full invite** on the desktop and paste it in the phone's
Nearby sheet. It carries the same certificate pin and high-entropy secret as
the QR, so multicast discovery and camera access are not required. A bare
numeric or base32 code is not a supported pairing input. The unused manual-code
codec does not imply an implemented provisional TLS pairing flow.

### Authenticating the first TLS connection

For both QR and pasted invitations, accept the certificate only when its actual
SHA-256 equals the out-of-band invitation pin. There is no provisional unpinned
transport. Discovery metadata alone cannot establish trust or enable controls.

Both inputs then perform a certificate-bound, mutual HMAC proof using the
out-of-band high-entropy pair secret. The protocol uses standard HMAC-SHA256
as a proof, not as a replacement encryption algorithm. The exact transcript
and active-MITM tests are security-critical implementation requirements.

1. Phone sends `pair.hello` with version, fresh 32-byte `clientNonce`, random
   `clientId`, bounded `clientName`, and the invitation's `pairId`. Do not send
   the secret itself.
2. Desktop sends `pair.challenge` with `pairId`, desktop ID and fresh 32-byte
   `serverNonce`. A challenge expires after 10 seconds and is usable once.
3. Define `LP(x)` as uint32 big-endian byte length followed by bytes. Transcript
   `T` is concatenated LP fields in this exact order: UTF-8 protocol name
   `meowwatch-companion-pair`, UTF-8 `1`, decoded desktop ID, decoded pair ID,
   decoded client ID, UTF-8 client name, client nonce, server nonce, and actual
   32-byte TLS certificate SHA-256. IDs/nonces use unpadded base64url on wire.
   The phone computes the certificate hash from its socket; it must never trust
   a hash supplied in `pair.challenge`.
4. Phone sends `pair.proof = HMAC(secret, LP("client") || T)`. Desktop checks
   it against its own certificate, challenge and invitation in constant time.
   Wrong proof, stale challenge or expired invitation closes the connection.
5. Only a verified proof opens the desktop approval prompt: **Allow [device]
   to control this MeowWatch session?** The prompt expires after 30 seconds and
   cannot outlive the invitation. The phone remains pending with no room data.
6. On approval, atomically consume the invitation, generate `tokenId` (16 bytes)
   and `deviceSecret` (32 bytes), persist the device record, then send
   `pair.accept` containing them plus `serverProof = HMAC(secret,
   LP("server") || T || LP(tokenId) || LP(deviceSecret))`. Persistence failure
   fails pairing. The phone verifies the proof before storing the certificate
   pin and device credentials or enabling any application stream.

An active MITM with a different TLS certificate cannot relay the proof to the
real desktop because the certificate hashes differ. It cannot recover a
128-bit random secret from the observed HMAC. This is why accepting a short
numeric secret or excluding the actual certificate from the proof is forbidden.
Limit pending challenges to 4 globally, failed proofs to 5 per invitation,
and incoming unauthenticated sessions to 10 per minute globally, with bounded
per-address limits. Do not reset global limits by reconnecting from a new IP.

## Reconnection, authorization and revocation

Paired connections require an exact certificate pin before any application
frame. Client starts with `auth.hello`; server sends a fresh `auth.challenge`
with nonce; client sends `tokenId`,
fresh client nonce and HMAC under its `deviceSecret`. Use a separate domain
`meowwatch-companion-auth`, version, desktop ID, token ID, both nonces and actual
certificate hash with the same LP encoding. Role labels `client` and `server`
separate the proofs. The exact auth transcript order is domain, version, desktop
ID, token ID, client nonce, server nonce, certificate SHA-256. The client proof
is HMAC(secret, LP("client") || T); `auth.ok` supplies a fresh 16-byte connection
ID and HMAC(secret, LP("server") || T || LP(connectionId)). Challenges expire
after 5 seconds, cannot be reused, and bind to the current
socket. Tokens never appear in discovery or ordinary command envelopes.

The initial implementation completes pairing without a control lease. The
phone verifies and securely saves `pair.accept`, closes that socket, and opens
a new pinned connection for `auth.hello`. No room data is sent on the pairing
connection. A connection selects one ceremony and cannot change phases by
sending an unrelated frame.

Each device record has durable revocation/deletion and a 30-day inactivity expiry.
Revocation first changes the authority state, then drops associated sockets,
invalidates pending/queued commands and deletes the stored secret. A new frame
must check that state before execution; passing authentication earlier is not
permanent authorization. Global Stop Nearby revokes active leases and closes
listeners/advertisements. Forget on phone deletes its local token; if connected,
`device.revokeSelf` also revokes it on desktop.

Send `ping` every 5 seconds; 15 seconds without incoming traffic marks the
connection lost and disables controls. Reconnect with bounded exponential
backoff and a fresh proof; never replay queued play/seek/chat after reconnect.
Certificate change, revocation, expiry and bad authentication require user
action, not endless retries. A phone disconnect does not leave the desktop's
Syncplay room or stop its movie: it only releases the companion control lease.

## Application frames and state

Maximum frame 64 KiB, maximum pending outbound data 256 KiB, finite nesting
and collection/string limits; reject invalid UTF-8, unknown required versions,
non-finite numbers and out-of-range positions. Slow readers are disconnected.
All times/positions are integer milliseconds. Use an independent monotonically
increasing `seq` for each authenticated connection direction.

Command example:

```json
{"v":1,"type":"command","seq":8,"id":"random-command-id","sessionEpoch":"desktop-session-id","method":"playback.seek","args":{"positionMs":42000}}
```

`sessionEpoch` changes on desktop room replacement/exit, preventing commands
queued for a previous room from touching the new one. Serialize commands;
recheck connection/device/session generation after every awaited step. Retain
at most 128 command IDs for two minutes per lease to deduplicate uncertain
same-connection retries. A repeated ID with different content is an error.
Never retry a timed-out user command automatically across connections.

| Method | Arguments / semantics |
|---|---|
| `state.get` | Return one coherent full snapshot; safe after reconnect |
| `playback.play`, `playback.pause` | Explicit desired state, never toggle |
| `playback.seek` | Nonnegative `positionMs`; clamp to known media duration; reject when no accepted media |
| `chat.send` | Nonblank text, maximum Syncplay 150-character limit; no optimistic received message |
| `chat.reaction` | Bounded allowlisted reaction identifier/emoji |
| `chat.typing` | Boolean, throttled; display expires after 4 seconds |
| `session.prepare` | Requested exact room identity, optional invite; requires desktop approval before replacing a different room |
| `controller.detach` | Release phone lease only; keep desktop watching |
| `device.revokeSelf` | Revoke this pairing and close the connection |

`session.prepare` completes only when the desktop joined the exact endpoint
and room and registered its live adapter. Use the existing secure join flow;
no independent scan for a supplied room. A server password, when needed, is
entered on desktop or sent only through this authenticated encrypted command
with explicit desktop consent, and is never echoed in snapshots. No shell,
filesystem browse, arbitrary file open, process launch or raw mpv command exists.

Direct-URL loading may be advertised later as `media.loadUrl` and must use the
desktop's accepted load coordinator, its restrictions and a clear consent UI.
V1 does not accept phone `file:` or `content:` URIs as desktop paths. The phone
shows **Choose this video's file on your desktop** when remote loading is not
supported. No media file bytes are transferred by this protocol.

Responses contain `id`, `ok`, `stateRevision`, and typed `error` if needed.
Native command completion is not proof that playback physically advanced;
the subsequent snapshot is authoritative. A timeout produces an uncertain
result, refreshes state and allows an explicit retry; it must not be labelled
successful. Background or foreground is not a new hosting session.

Snapshot fields:

```text
desktop: {id, name, capabilities[], protocolVersion}
session: {epoch, mode: local|synced, room?, server?, port?, username?, connection}
playback: {revision, sampledAtUnixMs, positionMs, durationMs?, playing,
           buffering?, status, media: {id, title, kind, shareableUrl?}?, error?}
participants: [{username, isSelf, ready?, mediaTitle?}]
chat: [{id, username, text, receivedAtUnixMs, system, isMine}]
```

Do not export raw local paths, file:// URIs, signed/token-bearing media URLs,
server passwords or debug logs. `shareableUrl` is opt-in and must exclude
credentials/tokens. Initial chat contains the newest 100 bounded messages;
thereafter send `chat.message`, `chat.reaction`, `chat.typing`, `presence`, and
coherent `state.snapshot` events. State events are capped at 4 Hz, with immediate
updates for play/pause/seek/error/room change. UI may interpolate position from
elapsed monotonic receive time, but commands use authoritative state.

Error codes: `version_unsupported`, `pairing_closed`, `pairing_expired`,
`pairing_denied`, `auth_failed`, `device_revoked`, `controller_busy`,
`session_changed`, `room_mismatch`, `no_media`, `not_connected`,
`invalid_argument`, `unsupported_command`, `rate_limited`, `native_failure`,
`command_timeout`, `permission_denied`, `lan_unavailable`, `storage_unavailable`. Authentication
failures reveal no token-existence detail. User copy is localizable and does
not expose raw exceptions, paths or secrets.

## Switching targets without a ghost participant

1. Discover/pair/authenticate while retaining the working phone session.
2. Compare desktop room identity with the phone's room. If different, request
   `session.prepare` and explicit desktop approval. Never silently adopt an
   unrelated desktop room or move it away from another user's session.
3. Desktop joins once through its existing route and returns a fresh accepted
   session snapshot. If it cannot change rooms automatically yet, the honest
   fallback is to show the room invite for manual desktop join, then recheck.
4. Pause phone playback, detach its bridge, deliberately disconnect its
   Syncplay client and wait for disposal. Keep the persisted Together Session
   ID/quota status. Only then enable companion controls and relay state/chat
   through the desktop. The temporary overlap must be bounded to handoff.
5. A failure before step 4 leaves the original phone session usable. A failure
   after it shows disconnected companion controls with explicit retry or
   **Watch on this phone**; it does not silently create another room.
6. Switching back detaches the companion lease, restores phone media/resume
   context, then securely rejoins once using the same persisted session ID.
   The desktop remains in its room unless its owner chooses to leave.

Controlling an existing desktop room is joining an existing experience and
does not spend a new mobile hosting allowance. Moving a mobile-hosted session
keeps its ID; the host's quota check must happen before a requested session
start or remote play, not anew on every target switch/reconnection. Do not
claim mobile Plus status from an unauthenticated desktop advertisement.

## Concrete desktop integration points

All paths below refer to the pinned desktop commit above. Add new transport,
pairing/identity, session adapter and tests under `lib/core/nearby/` and
`test/core/nearby/`; add a small pairing/device sheet under `lib/ui/nearby/`.
The desktop work belongs in a **separate focused PR/worktree**.

| Existing desktop path / symbol | Proposed connection |
|---|---|
| `lib/app.dart:114` `_joinAndOpenRoom` | Reuse for explicitly approved `session.prepare`; it owns secure join + route handoff. Its current Future lasts until the room route pops, so expose a separate joined/live-adapter signal for protocol readiness rather than awaiting the route lifetime. |
| `lib/ui/home_screen.dart:133` `_HomeScreenStateBase`, `:323` session creation | Register one `DesktopCompanionSession` adapter with the app-owned Nearby service after the route/session is accepted; unregister synchronously on leave/dispose. |
| `lib/core/session/session_services.dart` `SessionServices` | Reuse its existing `sync`, `chat`, `bridge` references. The companion must not instantiate another trio. Refresh adapter bindings during Local/Together changes. |
| `lib/core/video/video_core.dart:20`, `:108–110` | Read `state/stateStream`; route explicit play/pause/seek to the same core used by desktop controls. Existing desktop bridge already observes those local commands. Validate accepted source and command generation first. |
| `lib/ui/home_screen_media.dart:17`, `:66`, `:473` | `_loadedSource`, `_load`, `_announceLoadedFile` are the accepted-source/load path; future URL loading must go through these, not `VideoCore.load` directly. |
| `lib/ui/home_screen_sync.dart:137` `_initSyncSubscriptions` | Snapshot `_username`, `_peers`, `_peerFiles`, connection status coherently from this session's sources; clear stale membership during reconnect. |
| `lib/core/chat/chat_store.dart` | Relay `messages/stream/reactions/typing`; commands call existing `send/sendReaction/sendTyping`. Preserve server echo and sender identity. |
| `lib/ui/home_screen_body.dart:229` `PlayerMenuButton`, `lib/ui/player_menu_button.dart` | Add Nearby action/device control status using existing menu conventions and motion/accessibility rules. |
| `lib/core/data/app_support_dir.dart` `resolveAppSupportDir` | Namespace bridge nonsecret metadata and secure-storage keys with the existing isolated profile; never use the release key or updater files. |
| `windows/runner/` | Narrow platform adapter only if necessary for on-link prefix/private-network checks. Do not alter the updater or unrelated Windows startup behavior. |

Mobile adapters now use `NearbyDiscovery`, the protected pairing store,
`NearbyClient` and `NearbyDesktopTarget`. AppController switches its actual
target and session/chat providers together, with generation cancellation on
leave and retained phone playback/session identity for an explicit return.

## Required verification before claiming Nearby works

- Real generated certificate + `SecureServerSocket` + Android `SecureSocket`
  round trip; verify wrong/expired/changed certificate rejection and no
  command bytes before pairing/authentication. Test the actual pinned package
  versions and both Release Windows and Android builds.
- Pairing transcript vectors, role separation, tampered nonces/IDs/names,
  malicious-server certificate substitution, QR pin mismatch, replay on a
  different socket, expiry during approval, double consumption and global
  rate limits. A malicious relay with its own valid TLS certificate must fail.
- No command/state/chat before desktop approval; denial and secure-storage
  failure grant nothing. Revocation kills existing and queued actions and
  rejects reconnect even with a formerly valid secret.
- Address parsing and prefix boundaries, IPv4-mapped IPv6, DNS rebinding,
  VPN/public adapter selection, interface change, permission denied,
  malformed/oversized/slow frames, unknown methods and stale `sessionEpoch`.
- Two real mobile/desktop clients: mDNS and manual fallback, explicit pairing,
  accurate snapshots, bidirectional desktop/phone controls, peer-room sync,
  chat/reactions/typing, phone network loss/recovery and desktop restart.
- Target switch room counts: no lasting duplicate phone Syncplay user,
  unrelated desktop room requires consent, same quota/session identity survives,
  late connect/load/approval cannot resurrect an abandoned target.
- Logs and persisted artifacts contain no pairing secret, device secret,
  private TLS key, server password or signed media URL. Test isolated profiles
  so development cannot revoke the user's production pairings.

## Shared package evidence, 2026-09-16

`packages/nearby_bridge` is a standalone pure Dart package. Resolved production
dependencies: `basic_utils 5.8.2`, `crypto 3.0.7`; test runner `test 1.32.0`.
Its [README](../packages/nearby_bridge/README.md) documents stable public APIs,
adapter obligations, supported command arguments and the secure-store contract.

- **Confirmed:** 76 primitive/authority/TLS client/server tests pass on Windows
  ARM / Dart 3.12.0 with the actual local adapter selected for client tests.
  Generated RSA-2048 certificates complete an actual loopback
  `SecureServerSocket`/`SecureSocket` exchange of bounded JSON frames. Wrong
  pin, expired cert, incompatible ALPN and plaintext command attempts fail.
- **Confirmed:** Python `hashlib`-derived independent transcript vectors;
  different-certificate relay proof failure; nonce/identity/role separation;
  socket-bound one-use challenges; invitation/approval expiry; denial; double
  approval consumption; cancellation/expiry/close/stop during pending storage;
  revocation during delayed auth; single-controller reservation; heartbeat and
  room-generation invalidation; persistent inactivity and global rate limits.
- **Confirmed:** malformed UTF-8/JSON, duplicate keys, deep/large structures,
  lone surrogates, unsafe numbers, fragmented frames, partial EOF, unknown
  commands, invalid chat/seek/reaction args and sequence replay are rejected.
  Canonical numeric LAN addresses and actual-prefix boundaries are tested.
- **Confirmed:** `dart analyze --fatal-infos` reports no issues. Formatting and
  standalone tests run only within the package, without changing root app
  manifests or the dirty desktop reference checkout. No private keys are saved.
- **Confirmed:** Windows Release protected storage retains identity/credentials
  across separate processes and persists revocation across another restart.
  Native Windows interface/profile enumeration rejects the current Public
  network. Mobile target/controller behavior has regression coverage, including
  ownership, failed handoff, room mismatch and phone restoration.
- **Confirmed:** API 35 Android performs a real pinned TLS exchange, owner
  approval, fresh-client authentication, control and revocation. Native protected
  credentials and tombstones survive two app restarts; Android NSD observes a
  local test advertisement. These are same-device runtime checks.
- **Unverified:** physical cross-device LAN discovery, production desktop/phone
  pairing ceremony, and two-client
  ghost-participant acceptance. Test adapters and same-host encrypted sockets
  do not establish physical mobile-to-desktop acceptance.

The shared `NearbyServer` now implements strict phase dispatch, pre-handshake
admission (10/minute globally, 5/address), 256 KiB outbound buffering, 3-second
frame/write deadlines, authenticated command rate/queue limits and per-lease
deduplication. Its real TLS socket tests verify those boundaries, owner approval,
actual socket revocation, serialized commands with responsive heartbeat, and
late-command rejection after room replacement or shutdown. It subscribes to
authority closure events, calls `expire`, and revalidates leases around dispatch.
The desktop handler must also call the supplied `NearbyCommand.checkActive()`
after native waits and immediately before side effects, reject changed media
generations, redact snapshots and throttle routine events.
Exact client/server handshake and event fields are in [NEARBY_WIRE.md](NEARBY_WIRE.md).
Current command codec intentionally rejects `session.prepare` until an approved
desktop room adapter exists. Both supported pairing inputs are pinned full
invitations; provisional code-only pairing is not part of the shipped flow.

Self-revocation enters a terminal phase, immediately retires the control lease,
and emits one success receipt only after the durable tombstone write completes.
Failure or timeout returns no success and never restores command authority.
Secure-store failures stop the authority. A failed durable revocation must be
repaired before restarting Nearby; an in-memory invalidation cannot prove
revocation survives a restart when protected storage reports failure. Stored
last-use is refreshed at most hourly during active control; invitation,
challenge, approval and heartbeat deadlines use an injected monotonic clock.
