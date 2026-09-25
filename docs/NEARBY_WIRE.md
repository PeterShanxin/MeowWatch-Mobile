# Nearby wire schema v1

Shared server/client contract agreed 2026-09-16. UTF-8 JSON objects followed by
LF over certificate-pinned TLS, ALPN `meowwatch-companion/1`. Every object has
integer `v: 1` and string `type`. Handshake objects allow **only** the fields
listed below plus `v` and `type`; required fields cannot be null. Binary fields
are canonical unpadded base64url: IDs 16 bytes, nonces/proofs/certificate hashes
32 bytes, invitation secret 16 bytes, device secret 32 bytes.

## Pairing connection

| Direction / type | Additional fields |
|---|---|
| C → S `pair.hello` | `clientId`, `clientName` (1–64 runes, no controls), `clientNonce`; optional `pairId` |
| S → C `pair.challenge` | `desktopId`, `pairId`, `serverNonce` |
| C → S `pair.proof` | `proof` |
| S → C `pair.pending` | `expiresInMs` (integer 1–30000) |
| S → C `pair.accept` | `desktopId`, `tokenId`, `deviceSecret`, `serverProof` |

Only proof-verified requests reach desktop owner approval. The phone verifies
the server HMAC before protected persistence. Server sends `pair.accept`, then
closes the pairing socket. Pairing does not authorize application frames. The
phone reconnects with an exact stored certificate pin and starts authentication.

## Authentication connection

| Direction / type | Additional fields |
|---|---|
| C → S `auth.hello` | none |
| S → C `auth.challenge` | `desktopId`, `serverNonce` |
| C → S `auth.proof` | `tokenId`, `clientNonce`, `proof` |
| S → C `auth.ok` | `connectionId`, `sessionEpoch`, `serverProof` |

Use the exact LP/HMAC transcripts in `NEARBY_PROTOCOL.md` and shared
`PairingTranscript`/`AuthTranscript`. The auth server proof binds the returned
connection ID. The TLS certificate hash comes from the actual socket, never a
challenge field. Client checks the saved desktop ID before proving possession.

Before authentication, a fatal error frame is
`{"v":1,"type":"error","error":{"code":"auth_failed"}}`, followed by close.
No raw exception string, token existence detail, room state or log is returned.
Immediate authority revocation can close the socket before a best-effort error
frame is delivered; clients must treat EOF as failure, never successful auth.

## Authenticated connection

All following frames include integer `seq` and string `sessionEpoch`. Sequences
are independent per direction, start at 1 and must strictly increase (gaps are
allowed). `auth.ok` has no sequence number. Server immediately follows it with
`state.snapshot` at sequence 1. The epoch is the exact authenticated epoch;
room replacement closes the lease and requires fresh authentication.

| Type | Additional fields and direction |
|---|---|
| `command` | C → S: `id` (1–64 chars), `method`, `args` object |
| `result` | S → C: matching `id`, `ok` boolean, `stateRevision` nonnegative integer; exactly one of `result` object (success) or `error: {code}` (failure) |
| `state.snapshot` | S → C: `state` object in the snapshot schema of `NEARBY_PROTOCOL.md` |
| `chat.message`, `chat.reaction`, `chat.typing`, `presence` | S → C: `event` object carrying the corresponding bounded, redacted event |
| `ping`, `pong` | Either direction: no additional fields |
| `error` | S → C: `error: {code}`, fatal, followed by close |

Server answers `state.get` with `result.result: {"state": <snapshot>}`. Other
successful adapter commands return an object (normally `{}`). A result reports
completion/acceptance; snapshots remain playback truth. Server also sends a
fresh snapshot after successful playback/chat commands. Independent desktop
changes use handler events. Snapshot/chat content must exclude local paths,
server passwords, credentials and signed media URLs.

Server handles `controller.detach` and `device.revokeSelf`, sends their result
and closes that controller connection without leaving the desktop room.
Supported adapter methods/arguments are the shared codec's play/pause/seek,
chat.send/reaction/typing set. `session.prepare` is unsupported until an explicit
desktop owner approval/join adapter is implemented.

Send ping every 5 seconds. Valid sequence-checked incoming frames renew the
15-second lease; malformed frames never renew it. No outgoing traffic alone
renews a lease. Client answers server ping with pong and may also send its own
ping. Never replay a command automatically after reconnection.

Command IDs deduplicate only within one connection for 2 minutes, at most 128
entries. Same ID with different method/args/epoch is rejected. Same ID/content
gets the cached result with a new server sequence. Server serializes commands,
limits queued commands and rechecks lease/epoch before and after each await.
Timeout is uncertain, never successful; invalidate the connection so queued
commands and late native continuations cannot remain authorized.

Both adapters bound encoded frames to 64 KiB and queued writes to 256 KiB,
disconnect stalled writers/partial-frame senders, and close on malformed input.
The server applies LAN prefix and arrival checks before TLS setup, a 5-second
TLS/initial-hello deadline, and authority pairing/auth deadlines thereafter.

## Desktop adapter seam

`NearbyCommandHandler` provides `int stateRevision`, a synchronous coherent
`Map<String,Object?> snapshot`, `Stream<NearbyServerEvent> events`, and
`Future<Map<String,Object?>> handle(NearbyCommand command)`.
`NearbyCommand` exposes `id`, `sessionEpoch`, `method`, `args`, and
`checkActive()`. The handler calls `checkActive` immediately before and after
every awaited native action, and before/after synchronous chat actions.
Throw `NearbyException('no_media')` / other protocol codes for known failures;
unknown exceptions become `native_failure` without leaking their text.
`NearbyServerEvent(type, body)` uses full snapshot body for `state.snapshot`,
otherwise the social event body. Server adds envelope/sequence/epoch itself.
