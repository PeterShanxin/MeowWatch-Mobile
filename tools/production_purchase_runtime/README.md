# Production purchase journey

This acceptance gate renders the real `MainApp` using `openAppServices()`, its
normal native player, production RevenueCat adapter, and durable quota/history
stores. It operates onboarding, Start a room, media selection, play/pause,
paywall, settings restore, appearance and Leave room through product controls.
No production purchase/entitlement/quota test switches are added.

The journey consumes one free hosted session with an independently connected
real STARTTLS protocol peer, proves the next Start opens the paywall, performs
native Test Store cancellation/failure/success, invokes SDK restore through
Settings for the same current customer, selects and persists Cinema Noir, then
plays two additional distinct paid hosted sessions. Before the original final
Cinema Noir assertion, it selects and persists Glass Aurora, enters the first
paid production room with that theme still active, and sends the Movie night
`🎬` reaction through the product picker. The independently connected headless
TLS peer must receive the exact reaction control payload from the app's current
server username; a local callback or mock receipt cannot satisfy this check.
Cancellation and failure must expose the exact RevenueCat SDK error codes from
that purchase; generic UI
failure text cannot pass. Read-only controller, SDK and persisted ledger
observations establish the assertions. The peer observes real server playback
state but has no decoder.

## Runtime boundary

One API 35 Android emulator runs one production UI/native decoder and two TLS
clients in the same app process. This proves the production purchase/hosting UI
funnel, **not** two-device playback, a physical device, Google Play charging,
reinstall/lost-access entitlement recovery or process-restart persistence.
Restore invokes the actual SDK for the same customer in the current process
after invalidating its CustomerInfo cache, and proves that the already-active
entitlement remains active. Test Store restoration queries customer information;
it does not recover Google Play purchase history for a lost anonymous identity.

The runner sets and restores the selected emulator's display overrides to
1179×2556 at density 480. Native screenshots must have those exact submission
dimensions; no synthetic resizing is performed. Screen recording explicitly
uses 480×1040 at 2 Mbps so the odd screenshot width cannot break the video
encoder. `run.json` keeps the full native screenshot dimensions separate from
the requested recording dimensions and bitrate, and every completed segment is
rejected unless `ffprobe` confirms the requested encoded dimensions. This lowers
only recording cost; it does not establish that capture size caused any prior
duration shortfall.

The runner intentionally clears this package only after verifying the explicit
serial is an Android emulator. Use a disposable test emulator. The Test Store
SDK key defaults to the existing debug public configuration; never use a real
store purchase key with the native dialog automation.

```sh
python3 -m unittest discover -s tools/production_purchase_runtime -p 'test_*.py'
bash tools/android_multi_device/prepare_fixture.sh
flutter build apk --debug --target=integration_test/purchase_journey_test.dart \
  --dart-define=PURCHASE_JOURNEY_VIDEO_URL=http://10.0.2.2:18765/sync-fixture.mp4
bash tools/production_purchase_runtime/ci.sh
```

For an already running fixture server and explicitly selected emulator:

```sh
python3 tools/production_purchase_runtime/run.py \
  --serial emulator-5554 --apk build/app/outputs/flutter-apk/app-debug.apk
```

Artifacts are unique under `build/production-purchase-artifacts/<run-id>/`:
native screenshots, native-dialog XML/focus proof, raw segmented MP4s, Flutter
driver logs, `result.json` assertions and `run.json` orchestration results. The
screen recorder rotates every 70 seconds and retains start/finalization times;
transfer/rotation gaps are not advertised as continuous footage. Missing or
unfinalized footage fails the runner even if Flutter assertions passed. Each
segment is probed with `ffprobe`; its media duration may trail monotonic recording
time by at most 3 seconds, each rotation gap is capped at 15 seconds, and the
segments must cover at least 90% of the journey interval. A recorder that exits
early with a valid short MP4 therefore fails the gate. The
runner validates the complete UI evidence, three distinct durable session IDs,
one free/two paid records, actual TLS peer play and premium-reaction observations,
the persisted Glass Aurora room transition, and all native dialog outcomes before
reporting success. The journey now reports 12 verified steps and 12 native
screenshots: the original ten of each plus `glass-aurora-applied` and
`movie-night-reaction-sent`. Real acceptance still requires a
passing hosted run and visual inspection of its screenshots and recordings.
