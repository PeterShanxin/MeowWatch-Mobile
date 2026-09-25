# nearby_bridge

Portable Dart primitives for the MeowWatch LAN companion. These primitives do
not start an app service, implement discovery, or grant raw playback access.
See [the full protocol](../../docs/NEARBY_PROTOCOL.md) for product integration.

## Public seams

- `LanIpv4Address.parse`, `LanEndpoint`, `LanSubnet.requirePeer`: canonical
  RFC1918/link-local IPv4 and actual interface-prefix validation. Reject public,
  loopback, IPv6/mapped IPv6, alternate syntax, network/broadcast addresses.
  The native adapter supplies the real prefix; private IP alone is insufficient.
- `TlsIdentity.generate`: RSA-2048/SHA-256 self-signed identity generated in an
  isolate without files. `createServerContext` sets minimum TLS 1.2, server-auth
  EKU, non-CA constraints and ALPN `meowwatch-companion/1`.
- `connectPinnedTls(address, port, certificateSha256)`: no application bytes
  before exact actual-certificate pin, validity and ALPN verification. This is a
  **transport primitive**: validate its numeric destination with `LanSubnet`
  first. It deliberately permits loopback for real socket tests. It never
  provides a provisional/unpinned connection or plaintext fallback. Its
  five-second deadline covers TCP and TLS together and closes the retained raw
  connection on timeout. `startPinnedTls` returns a cancellable attempt; the
  client owns it until connection completes, including across disconnect,
  disposal and replacement attempts.
- `RawSecureTransport` (from `transport.dart`): the verified TLS byte stream
  returned by the connection primitives. Pausing its subscription stops raw
  reads; writes handle partial acceptance and propagate failure to pending
  flushes. The caller owns its lifetime and must destroy it on abandonment.
- `PairingInvitation`: explicit `encodeQr`/`decodeQr`, `manualCode`, and
  `decodeManualCode`. QR uses canonical base64url JSON under `meowwatch-pair:`;
  code uses canonical Crockford base32 (26 characters, optional spaces/hyphens).
  All IDs are 16 bytes, nonces 32, invitation secrets 16, device secrets 32.
  No short numeric secret is accepted. Secret-bearing objects redact `toString`.
- `PairingTranscript`, `AuthTranscript`: unambiguous length-prefixed HMAC-SHA256
  transcripts, role separation and actual peer-certificate binding. Callers
  use `constantTimeEqual` for received proofs, never ordinary list equality.
- `NearbyFrameCodec`, `JsonLineDecoder`: strict UTF-8 LF frames, 64 KiB excluding
  LF, max depth 12, 2,048 values, 128 keys/object, 256 array items, 4,096 UTF-16
  units/string. Reject duplicate keys, lone surrogates, nonfinite/unsafe numbers,
  unsupported versions/types and invalid commands. `FrameSequence.accept`
  rejects repeated/decreasing authenticated sequence numbers.
- `NearbyAuthority`: socket-bound pairing/authentication and revocable single
  controller lease. Inject `NearbySecretStore`; optionally inject
  `MonotonicClock`, `SecureRandom`, `utcNow` for deterministic boundary tests.
- `NearbyServer.bind`: production TLS listener on the selected `LanSubnet`,
  wrapping a `NearbyCommandHandler` and an explicit owner-approval callback.
  It owns socket/authority lifecycle, strict handshake dispatch, pre-TLS
  admission, heartbeat, command serialization/deduplication and bounded output.
  `NearbyServer.forTesting` is an explicit loopback test seam, never shipping
  network policy. Exact frames are in [NEARBY_WIRE.md](../../docs/NEARBY_WIRE.md).

## Authority integration order

1. Bind only a selected numeric LAN address with `identity.createServerContext`.
   Check every accepted peer against the actual adapter prefix. Reject wrong
   ALPN server-side too. Apply arrival limits before expensive TLS handshakes
   in the transport as well as this authority's post-handshake limits.
2. Subscribe to `connectionsToClose` **before accepting sockets**. Call
   `openConnection(peerAddress: socket.remoteAddress.address)` exactly once per
   socket and keep its returned random ID privately associated with that socket.
   Never accept a connection ID from an inbound frame. Close the actual socket
   when instructed; call `closeConnection` on EOF/error/cancel.
3. Wait for `pair.hello` or `auth.hello`. A connection chooses exactly one
   ceremony. Pairing invokes `beginPairing`, returns its challenge, then invokes
   `verifyPairingProof`. Only a returned `PendingApproval` may appear in desktop
   consent UI. Until then, send no session, playback, roster or chat data.
4. Owner approval calls `approvePairing`. Persistence succeeds before credentials
   can be returned. Send `pair.accept`, have the client verify `serverProof` and
   securely persist credentials/pin, then close that pairing socket. **Pairing
   itself has no controller lease.** Reconnect and authenticate normally.
5. `auth.hello` invokes `beginAuthentication`; `auth.proof` invokes `authenticate`.
   Verify `auth.ok` server proof client-side before attaching app state. Auth
   server proof includes the returned fresh connection ID. On any malformed
   field/proof/state error, close the connection; do not continue the ceremony.
6. For each authenticated frame, validate sequence and `sessionEpoch`, call
   `requireLease`, then `await recordActivity`. Check `requireLease` again after
   **every awaited operation** and before executing/returning a command result.
   The lease is an authority-owned object; no method accepts a wire-provided
   token as equivalent authorization. `replaceSession` invalidates old handles
   and disconnects the controller, which must authenticate into the new epoch.
7. Send ping every 5 seconds and call `expire()` from the transport heartbeat
   timer. A lease expires after 15 seconds without valid inbound activity.
   `recordActivity` refreshes stored last-use at most hourly; it may fail and
   must be awaited/handled. Persistent inactivity expires after 30 days.
8. `revoke(tokenId)` immediately invalidates authority/lease, then persists
   removal. Store writes are serialized so a delayed authentication update
   cannot overwrite a later revocation. `stop()` is terminal for this authority
   and drops every connection; `dispose()` also drains storage/closes streams.

`NearbySecretStore` must atomically store credentials and durably revoke them.
Use platform-protected storage scoped to the chosen development/user profile.
A storage failure stops this authority and reports only `storage_unavailable`.
If persisting revocation fails, do not restart/re-enable the service until the
store has been repaired and the revocation durably applied. No library can
claim reboot-safe revocation after its durable store reports failure. This
package intentionally has no production in-memory or plaintext storage fallback.

## Server guarantees and remaining application responsibilities

- `NearbyServer` validates exact phase-specific handshake/control keys, then
  routes typed fields through the authority. No application state/command is
  exposed before authentication, including while owner approval is pending.
- The server bounds queued output to 256 KiB, partial-frame assembly and socket
  writes to 3 seconds, TLS/initial hello to 5 seconds, queued frames to 32,
  commands to 20/second and 16 pending, and cached command IDs to 128/2 minutes.
  Admission allows 10 arrivals/minute globally, 5 per address. Revocation and
  room replacement close the real socket and invalidate pending continuations.
  The server retains each underlying raw socket during its TLS handshake, so
  the five-second deadline and server shutdown release silent peers too.
  A command timeout returns an uncertain error and closes its lease/queue.
- The desktop handler still owns redacted/coherent snapshot generation, a
  maximum 4 Hz for routine state events, and `checkActive()` around every await.
  The server can reject oversized output; it cannot infer whether an arbitrary
  application's string is a secret. The handler must obey the snapshot contract.
- Current command codec supports state, play/pause/seek, chat/reaction/typing,
  detach and revoke-self. `session.prepare` deliberately returns
  `unsupported_command` until an owner-approved desktop join adapter is wired.
  Seek positions are bounded to seven days and must be clamped to actual media
  duration by that adapter. Reaction allowlist is `❤️ 😂 😮 😢 👏 👍`.
- mDNS, native prefix enumeration, Android permissions, Windows firewall,
  secure-storage adapters, QR UI, manual provisional pairing-only transport,
  owner consent UI, snapshot redaction and actual media/Syncplay integration.
- The phone must dispose its own Syncplay participant before activating the
  companion target. This package never creates a Syncplay client.

## Verification

From this directory only:

```powershell
dart pub get
dart format --output=none --set-exit-if-changed lib test
dart analyze --fatal-infos
dart test
```

Real socket tests on Windows ARM with Dart 3.12.0 exercise generated
certificates and encrypted JSON roundtrips. Negative socket tests reject
wrong pins, expired certificates, wrong ALPN and plaintext commands. No private
keys are written to disk. These desktop Dart VM tests use loopback and an
explicit local virtual adapter; they do not establish Android or physical
cross-device LAN behavior. Server socket tests additionally cover
approval, authentication, forbidden early commands, command deduplication and
ordering, revocation of real sockets, native timeouts, late work after room
replacement/shutdown, pre-handshake admission, partial-frame deadlines and
bounded output backlog. Client tests cover pending-handshake cancellation,
replacement attempts and a complete pairing/authentication flow. The raw
transport is exercised with a paused peer, 8 MiB of exact-content output and
cancellation of a pending flush. See the main repository's delivery status for
the latest verified counts and platform evidence.

Two verified compatibility details: `basic_utils` 5.8.2's optional `keyUsage`
encoder emits a BIT STRING rejected by BoringSSL; omit that optional extension
while retaining server-auth EKU and non-CA constraints. On this Dart runtime,
configure server ALPN on `SecurityContext.setAlpnProtocols(..., true)`;
`SecureServerSocket.bind(supportedProtocols: ...)` alone yielded no negotiated
protocol. The connector rejects missing ALPN rather than weakening the check.
