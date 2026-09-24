# Delivery status

Last updated: 2026-09-25 (Asia/Shanghai). **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Verified on emulators | fdebec3 passes normal API 29/35 debug and API 35 release clean install in hosted run 36044617989. These are normal lib/main.dart APKs. Physical-device acceptance remains separate |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public AGPL-3.0 repository. Hosted Check 36054666023 at 0454176 passes the secret scan, formatting, analysis, 782 app tests, 87 Nearby tests and 14 platform tests. Final artifacts and repository closeout remain open |
| 3 | Clear first-launch create/join | Verified on emulators | 6e46041 passes all five first-use/layout journeys. Fresh 9a3fc05 Together 36037966143 passes actual Start, invitation review and Join on independently running phone/tablet emulators |
| 4 | Two real clients repeatedly play/pause/seek in sync | Verified on two emulators; debug recovery follow-up open | fdebec3 Together 36053642428 passes all 26 host and 25 guest stages with repeated two-way controls. Settled native positions match at 12,416, 53,361 and 55,242 ms. Profile network 36055097185 passes at 0454176. Debug network restoration is being verified separately; position agreement does not establish identical decoded frames or physical hardware |
| 5 | Real-session chat/reactions/presence | Verified on two emulators | 9a3fc05 passes repeated real-keyboard chat, presence, confirmed peer links and actual player/reaction viewport bounds. 6e46041 Test Store journey verifies a premium reaction received by a real TLS peer |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | fdebec3 normal release lifecycle and foreground audio focus pass. Profile network 36055097185 at 0454176 passes real radio loss, automatic pause, no-autoplay rejoin and explicit replay/Pause/Seek. The debug fixture previously created a second cellular handover outage; staged Wi-Fi restoration passes, but the debug visual gate missed an SDK Setup ANR and is being corrected. Physical and transient-focus acceptance remain open |
| 7 | Local Mode and Continue Watching | Partial | 6e46041 normal lifecycle restores 45 seconds in a new process without autoplay. 56fcd32 SAF relaunch 36039255967 retains the real content grant and restores 8 seconds. The same-source history restoration fix at 5347142 passes unit/widget checks and the standard-layout native journey 36041063625. Physical playback acceptance remains open |
| 8 | Secure phone-to-desktop discovery/pair/control | Partial | 6e46041 Android Nearby 36037410146 passes real pinned TLS pairing/control/revocation and protected persistence. Desktop f5a9103 clean Release builds and its actual Windows UI was inspected; dba4b57 updates its dependency pin and passes hosted Windows CI and 1,494 tests. Physical Android-to-Windows discovery/pair/control/revoke/restart proof remains open |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | 6e46041 production Test Store 36037410075 passes 12 stages, one free and two Plus hosts, native cancellation/failure/success, a premium reaction and same-customer Restore. Same-customer relaunch/expiry 36037410042 passes. Physical and Play-production evidence remain separate; the earlier anomalous Restore result remains historical and unexplained |
| 10 | Correct daily quota and session continuity | Verified in native flows and tests | Native purchase verifies one free plus two distinct Plus sessions. fdebec3 Together verifies joining, shared links, media recovery and history do not recharge. Profile network 36055097185 retains the original quota ledger across a real outage and reconnect |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | 6e46041 passes five viewport journeys and normal-release phone/tablet fullscreen. 9a3fc05 native Together verifies complete player/reaction bounds with tablet keyboard inset; original frame review shows the full heart and video. Source frame hashes are verified in hosted reviews. Final film motion and physical checks remain open; the SDK candidate is unadopted |
| 12 | Reliable Cast or exact blocker and fallback | Partial | Android sender and same-room handoff are implemented. Actual receiver acceptance awaits hardware; phone playback fallback is available |
| 13 | No placeholders, dead ends or silent failures | Partial | 6e46041 first-use/layout and purchase flows pass. 9a3fc05 Together verifies readable media errors, Choose another video recovery and shared-link confirmation. 5347142 makes same-source restoration visible and disables stale controls; native journey 36041063625 passes. Final-film inspection remains open |
| 14 | Clean-install full demo rehearsal | Partial | fdebec3 Together 36053642428 passes all 26 host and 25 guest stages on standard phone/tablet layouts. Profile network 36055097185 passes. The debug foreground-visibility gate and 98-second final edit remain under verification; prior film candidates are retained |
| 15 | Shipaton submission confidence | Partial | Brand kit and original-size submission screenshot are prepared. Final under-two-minute film, full rehearsal, physical gates and remaining eligibility/legal checks remain open |

## Current verification

The fresh `fdebec3` cohort passes Check `36044618584`, normal installation,
native playback, Nearby, five viewport journeys, the runtime matrix, normal
release lifecycle, foreground audio focus, phone/tablet fullscreen, Test Store
purchase, same-customer RevenueCat relaunch/expiry and SAF local-file relaunch.
Network debug `36044617832` fails while the independent UI observer returns
`root_missing` on all 16 capture attempts at `initial-ready`. The application
retains focus and its PID; no playback result is available. Its unchanged
second attempt passes the initial outage, then encounters a second real network
loss: restored cellular network 102 is replaced by Wi-Fi 103, and Android's
30-second linger expiry closes the old sockets during replay. The app correctly
pauses again. The runner now waits for two matching connected default Wi-Fi
observations before restoring cellular data, with a 30-second limit and exact
original-state cleanup on failure. All 45 runnable local mocked radio contracts
pass; one POSIX-only check is skipped on Windows. Native debug `36057193484`
proves the staged restore and completes internal playback assertions, with
initial convergence in 1.858 seconds and replay in 1.749 seconds at 35,512 /
35,213 ms. However, original screenshots and focused-window state reveal a
Google SDK Setup ANR over the app from initial-ready through recovery. The
runner failed to reject the foreign focused window, so **this green run is not
accepted as unobscured UI proof**. A scoped foreground guard and reuse of the
existing emulator-only setup recovery are implemented at `4db3518`. Captures
now require exact MainActivity focus in raw and observer windows plus app-only
native XML. An exact SDK Setup ANR may receive one bounded close after fresh
identity/window checks, with originals retained and new unobscured evidence
required. Other or ambiguous dialogs fail. The receipt discloses any recovery.
All 53 runnable mocked contracts pass locally; one POSIX-only check is skipped.
Hosted debug run `36060546361` successfully prepares the exact SDK Setup ANR
before app installation and requires no in-run recovery. All captured app
windows are unobscured MainActivity. Initial playback converges in 1.591 seconds;
real radio loss, automatic pause, stable no-autoplay reconnect and retained
controllers/quota pass. The complete run fails because a persistent sync-timeout
snackbar covers Play after reconnect. The original screenshot is retained;
peer and teardown errors are empty. Ordinary app notices now explicitly expire
after eight seconds (screen-reader navigation retains manual Dismiss), and sync
errors use recovery guidance instead of raw exception text. Three added
regressions and the unchanged native replay gate await hosted verification.
Repeated identical notices share the original expiry instead of extending it,
so repeated errors cannot permanently hide controls; a later occurrence after
dismissal starts a fresh notice. The Local audio-focus runner now retains its
permanent-loss case and appends independent transient loss/automatic-resume
acceptance with fresh nonce/UID/PID and current AudioService proof. All 29
lightweight Python contracts pass. A 180-second version of the same source
provides room for both cases without changing pause/recovery deadlines. Native
execution is still required; this does not establish Together-room focus behavior.
Profile `36044653778`
passes initial playback, radio
loss, automatic pause and no-autoplay reconnect, then fails explicit replay:
all 198 position reads succeed, but the closest pair is 1,105 ms apart and the
last is 54,953 / 53,416 ms. Peer and teardown errors are empty. These failures
are retained separately, not classified as the same defect.

The slower guest becomes Syncplay's ordinary room setter after buffering;
its first corrective seek buffers again, then its own room anchor cannot
meaningfully advance it toward the host. Host rate correction instead needs
to close the gap. It spends only about 8.5 seconds at 0.95 between native
buffering intervals. The new `0454176` correction preserves the existing
0.90 band until the lead falls below 900 ms, keeping the original 25-second
window, fresh-heartbeat checks and immediate 1x restoration on buffering.
A source reviewer identified an exit-condition early return; it is fixed and
covered for recovery below 900 ms followed by drift back to 1,100 ms. An
earlier diagnostic at `64c2f5e` fails with 1,150 ms after five modeled seconds;
the final regression covers the retained strong band through moderate drift.
Hosted Check `36054666023` passes all **782 app, 87 Nearby and 14 platform
tests**, formatting, analysis, media contracts and the secret scan. Fresh
profile network `36055097185` passes on one API 35 AVD with two real TLS clients
and native decoders. Initial playback converges in 7.561 seconds at 4,551 / 4,183
ms, and explicit replay after the outage converges in 5.531 seconds at 39,733 /
40,459 ms. Automatic pause, no-autoplay rejoin, explicit Pause/Seek, unchanged
controllers/quota and complete teardown pass; peer/teardown errors are empty.
This run predates the staged radio restore and does not verify that harness
change. Its original offline/recovery screenshots and all four focused-window
observations are unobscured MainApp; the later debug SDK-setup obstruction does
not invalidate that profile evidence. No native threshold is relaxed.

Together `36044618079` reports both app tests passed, but the tablet ADB
recording connection terminates and its recorder exits 255 during final result
recovery. Concurrent low-memory activity does not establish which process
caused the disconnect. The incomplete journey is not accepted as a pass.
Run `36053642428` passes all 26 host and 25 guest stages with standard phone/tablet
layouts and smaller native recording output. Settled native positions match at
12,416, 53,361 and 55,242 ms. Each device records one complete segment; no recorder
restart is required. The routine Together workflow now defaults to this compact
capture without changing UI geometry or acceptance checks. Hosted original-frame
review `36056723226` strictly decodes both sources and all 95 exported PNG hashes
match. Inspected originals show complete tablet video/controls with the keyboard
open, readable shared-link confirmation and history resumed at 1:07. Source
buffering and held-frame gaps remain visible; this is sampled visual evidence.

The 116-second film renders in `36044649586` and strictly decodes all 3,480
frames. SHA-256:
`f150fb588fd98468543ba2295e38ee996e69c5f6dda9d43a016530fadbb530cc`.
All seven native source pins match and all 29 exported samples are inspected.
Framing and captions fit; visible buffering, held frames and a source reopening
in the closing room excerpt still need editorial review. This is not final
motion acceptance or proof of identical decoded frames between devices.
The 100-second edit passes hosted render `36057684349` and strict decoding of
all 3,000 frames. Its 25 samples are reviewed (16 exactly match prior reviewed
PNGs, nine inspected directly); purchase activation and Restore are clear.
The appearance and closing-room excerpts still reach unrelated loading/picker
actions. The 98-second edit passes hosted render `36059267954` at `4dfd3e0`:
all 2,940 frames strictly decode, seven native source pins match and the EDL
matches the repository. SHA-256:
`5ced046aacf9f55a9b8be9344e27fd3a3266056c298e712ef2ce2b971d5c92c4`.
All 42 shot-boundary PNGs have verified hashes and are visually inspected.
The 25 periodic samples include 19 exact matches to previously reviewed images
and six newly inspected images. Appearance ends on the applied theme; the last
native cut ends in the second Plus room. Loading and held frames remain, and
full-motion acceptance stays open. Local review uses static PNGs only; no build, emulator
or video decoder runs on the user's computer.

Earlier convergence investigations, regression receipts, native cohorts and
film candidates remain in [Acceptance history](ACCEPTANCE_HISTORY.md#archived-september-25-verification-through-the-fdebec3-cohort).
Failed attempts and unadopted SDK experiments remain identified as such. The
normal app uses unmodified Flutter 3.44.0 / Dart 3.12.0.

## Desktop and submission artifacts

The desktop companion at `f5a91035973c7d8f1c2a20a6a5acd1e22fc70c8e` builds
from a fresh detached checkout with locked dependencies and official Flutter
3.47.2. Its complete unsigned Windows x64 review ZIP includes an isolated-profile
launcher, license and hashes. The normal Release window, Home, Settings, Local
Mode and player menu were captured and visually inspected. This is not physical
Android-to-Windows LAN acceptance. [Desktop PR #279](https://github.com/PeterShanxin/MeowWatch/pull/279)
remains draft. Requested Copilot review returned an account-quota failure and
performed no review; it is neither an approval nor a pending review.

The companion at `dba4b57` adopts the `bd931d5` dependency pin and passes 38 Nearby tests,
analysis and a normal Windows Release build. The first full local test process
ended with incomplete tests; a separate retained run completed **1,494 tests**
with exit zero. Its original log and exit receipt are retained. Hosted Windows
[Analyze & Test](https://github.com/PeterShanxin/MeowWatch/actions/runs/35988145930)
and Package Check also pass at `dba4b57`. Fresh native/manual acceptance remains
a separate gate before merge or release.

The selected navy/cream/blue icon kit includes Android adaptive/themed icons,
SVG/PNG and desktop ICO. The original 1179x2556 submission screenshot has no
frame. The separately audited purchase chapter is 42 seconds, with Test Store and
headless-peer boundaries disclosed, using original `2fc38317` recordings. Its
1,260 frames decode and pass source-clock correspondence checks; 53 output
samples were inspected. A browser replay ran uninterrupted from 0:00 to 0:42,
with screenshots checked at 0, 14, 28, 39 and 42 seconds. This is sampled visual
inspection, not a claim that every frame was visually inspected.
SHA256 is `b0cdadd718b5782e99af65ee1fb4ff18b43dcee6bfeff6140a0bc0198263a50d`.
Earlier 43-second and 40.2-second `9b7e9ed` previews remain historical.
The separately accepted `300ca2e` paired recording is 216.667 seconds, with its
original timing gaps visible. The `2fc38317` phone guide/local-player recording
from run 35236920763 has been copied unchanged into the local showcase; its
SHA256 is `73c2a9c928c597d7f30e502f9811b6da1189d6d12b00ae2ca6ef3638e0d12a47`.
Hosted film run `36017540928` renders the pinned 32-second recording review
from c53fc6a Together originals without starting Android. Its 960-frame
1920x1080 H.264 output passes strict full decode; the independently recomputed
SHA-256 is `bad6295ccf57cb1c5c9b99c281d37a2115ededf18dfbdc9e24eb9f9961ee77b7`.
One exported full-size paired frame was inspected for framing and legibility.
This is a cloud-render rehearsal, not the final film or full motion acceptance.
The final under-two-minute submission edit and full clean-install rehearsal
remain open. Historical runs and asset provenance are preserved in
[Acceptance history](ACCEPTANCE_HISTORY.md).

## Human/external dependencies

- The entrant confirmed active student status, local age of majority and access to an academic email. Remaining residency/ownership/conflict conditions and final legal acceptance are separate checks.
- RevenueCat login/Test Store catalog setup and user acceptance of the Android SDK license are complete. RevenueCat email confirmation remains visible.
- Physical Android, trusted physical LAN and Cast receiver availability remain unconfirmed. Emulators and virtual network adapters are not substituted for this evidence.
- Desktop required native/manual review gates remain applicable before merge or release.

## Live development recording

At September 24 21:26 UTC the current bounded two-fps recorder has about 148 MB
persisted. The latest scoped resource check finds about 10.4 GiB free RAM and no
local Dart, Java, FFmpeg or Android emulator. The selected image is a single
static phone/tablet frame from the reviewed 100-second film candidate; it is
labelled captured evidence, not live Android. Historical recording gaps below
remain part of the record.

Following two reported machine freezes, local heavy work is serialized and
Android builds, emulator runs and full regression suites use hosted CI. No
Flutter, Gradle or emulator process was running at the September 24 10:20 UTC
inspection; roughly 10 GiB RAM was free. This does not establish the cause of
the earlier freezes. One read-only reviewer handles bounded source/log work.

The showcase now supports `--evidence-only`, disabling live ADB subprocesses.
The evidence library loads media only after selection and retains unchanged
cards, removing the former 15-second recreation of every video/image element.
The load regression fails before the change and passes afterwards; all eight
showcase contracts pass. The current viewer uses one original still image and
the existing two-fps silent canvas recorder. A recording gap after the last
08:10:40 UTC saved chunk is retained; capture resumed at approximately 10:30 UTC.
A later browser-heartbeat gap from 11:01:00 to 12:51:49 UTC is also retained in
the original manifest. Capture then resumed without replacing the file. No
cause is inferred for that gap or the reported machine freezes. At 12:52 UTC,
approximately 9.97 GiB RAM was free and the showcase service used 21.4 MiB.
Video frame extraction now runs on hosted CI; local review reads only images
and metadata. New verification does not start a local build or emulator.

The browser upload chain also now has an explicit four-chunk/16 MiB ceiling
and a 15-second timeout for each of at most three attempts. Overflow or failed
uploads stop recording, release queued blobs and capture tracks, and retain an
interrupted manifest. The previous source reproduces unbounded enqueueing; all
eight showcase tests pass with the new overflow/timeout cases, and independent
source review finds no ordering or final-flush regression. This is a verified
resource bound, not a diagnosis of the reported machine freezes. The old
recording safely ends at 13:50:29 UTC with 174 persisted chunks and no unflushed
tail. A single-page update starts the bounded recorder at 13:50:44 UTC; the
approximately 15-second transition is disclosed rather than called continuous.
The new session has saved chunks and keeps the one-still, two-fps view.
A further 22.392-second heartbeat gap, 16:01:49.551–16:02:11.943 UTC on
September 24, is retained in that session's manifest. At 16:40 UTC recording
remains active with 336 persisted chunks. The showcase service uses about 22 MiB
at BelowNormal priority; no local Java, Dart, FFmpeg or emulator process was
present in the latest scoped process check. These observations do not diagnose
the earlier freezes or establish uninterrupted capture.

The initial recording began when the local Codex showcase opened. Its last
saved chunk is September 18; a new recording started on September 24 after the
development pause. This gap is retained and is not continuous recorded work.
The viewer
labels captured native footage, missing devices and recording gaps. The unchanged
`2fc38317` guide/local-player and purchase source recordings are available there
and have been replayed inside its running 2 fps silent canvas capture. The
118-second Review Preview is available in the resumed browser canvas. The capture
does not record microphone/desktop or
reconstruct earlier unrecorded development. The final demo will use actual
phone/tablet footage with simple frames; submission screenshots remain unframed.
