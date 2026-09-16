# Hosted quota + RevenueCat runtime

This runner verifies the full hosted-session boundary on one Android API 35
emulator:

- creating a room and playing alone do not consume the daily host allowance;
- a real peer joins through public STARTTLS and both native decoders advance;
- the first Together Session consumes the one free daily host;
- reconnect and disk-backed service reopen preserve that session and quota;
- a distinct hosted session is denied before purchase;
- native Test Store cancel and failure preserve the room and quota;
- a real Test Store purchase activates `meowwatch_plus`, restore retains it,
  and two distinct paid hosted sessions work.

The host and guest are two real TLS clients and two native video targets in the
same Flutter application process. This run is emulator evidence and must not be
reported as a two-device or physical-device test. No entitlement, receipt,
customer identity, or quota allowance is injected by the runner.

The harness enables native audio mixing before creating either decoder and
restores the default at teardown. Two players in one process otherwise compete
for the same Android audio focus. Before connecting to Syncplay or RevenueCat,
it renders two native video textures and requires each decoder to advance at
least another 1.5 seconds after the second starts, within 35 seconds, without
issuing another play command. Explicit buffering can recover; an unbuffered
pause lasting two seconds fails. This preflight does not replace the later
synchronized playback assertions.

`result.json` retains a bounded `decoderCoexistence.transitions` trace even when
the preflight fails. The same entries are logged as `HOSTING_DECODER`, including
actual playing/buffering flags, position, player errors and application lifecycle.

CI prepares the reviewed 90-second media fixture, builds
`integration_test/hosting_purchase_test.dart` with the public RevenueCat Test
Store key, and then runs:

```sh
bash tools/hosting_purchase/ci.sh \
  --serial emulator-5554 \
  --apk build/app/outputs/flutter-apk/app-debug.apk
```

Evidence is written to `build/hosting-purchase-artifacts/<run-id>/`. It includes
Flutter screenshots/result data, native purchase-dialog screenshots and
recordings, the Flutter drive log, APK hash, and `run.json`. The fixture server
state is retained at `build/hosting-purchase-fixture-server/`.
