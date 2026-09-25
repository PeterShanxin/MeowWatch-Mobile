# Delivery status

Last updated: 2026-09-25 (Asia/Shanghai). **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Verified on emulators | fdebec3 passes normal API 29/35 debug and API 35 release clean install in hosted run 36044617989. These are normal lib/main.dart APKs. Physical-device acceptance remains separate |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public AGPL-3.0 repository. Hosted Check 36074183204 at 29eafe2 passes the secret scan, formatting, analysis, 814 app tests, 87 Nearby tests, 14 platform tests and independent native observer SDK compilation. Final artifacts and repository closeout remain open |
| 3 | Clear first-launch create/join | Verified on emulators | 6e46041 passes all five first-use/layout journeys. Fresh 9a3fc05 Together 36037966143 passes actual Start, invitation review and Join on independently running phone/tablet emulators |
| 4 | Two real clients repeatedly play/pause/seek in sync | Partial; current replay convergence failed | fdebec3 Together 36053642428 passes all 26 host and 25 guest stages with repeated two-way controls. Settled native positions match at 12,416, 53,361 and 55,242 ms. Profile network 36055097185 passes at 0454176. Current 29eafe2 normal network 36074182939 fails replay convergence after an otherwise healthy paused rejoin; the bounded correction and failed-source rebuilding still need native acceptance. Position agreement does not establish identical decoded frames or physical hardware |
| 5 | Real-session chat/reactions/presence | Verified on two emulators | 9a3fc05 passes repeated real-keyboard chat, presence, confirmed peer links and actual player/reaction viewport bounds. 6e46041 Test Store journey verifies a premium reaction received by a real TLS peer |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | Normal release lifecycle passes at fdebec3; permanent and transient foreground audio focus pass in 36063562267 at f56c8e8 with original UI/AudioService evidence. Profile network 36055097185 at 0454176 passes real radio loss, automatic pause, no-autoplay rejoin and explicit replay/Pause/Seek. Current 29eafe2 network replay misses the 30-second convergence gate; lifecycle 36074183011 returns paused but exceeds the four-second HOME tolerance. Both remain under investigation. Physical and Together-room transient-focus acceptance remain open |
| 7 | Local Mode and Continue Watching | Partial | 6e46041 normal lifecycle restores 45 seconds in a new process without autoplay. Fresh 29eafe2 SAF relaunch 36074182994 retains the real content grant and restores 8 seconds; the original restored-player screenshot is reviewed. The same-source history restoration fix at 5347142 passes unit/widget checks and the standard-layout native journey 36041063625. Physical playback acceptance remains open |
| 8 | Secure phone-to-desktop discovery/pair/control | Partial | Fresh 29eafe2 Android Nearby 36074183032 passes pinned TLS pairing/control/revocation and protected persistence across three processes on one emulator. Desktop f5a9103 clean Release builds and its actual Windows UI was inspected; dba4b57 updates its dependency pin and passes hosted Windows CI and 1,494 tests. Physical Android-to-Windows discovery/pair/control/revoke/restart proof remains open |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | Fresh 6ad19ac production Test Store 36071310593 passes 12 stages, one free and two Plus hosts, native cancellation/failure/success, a premium reaction and same-customer Restore after cache invalidation. Original evidence and six selected screens are reviewed. Same-customer relaunch/expiry 36068920015 passes at 48e5a65. Physical and Play-production evidence remain separate; the earlier anomalous Restore result remains historical and unexplained |
| 10 | Correct daily quota and session continuity | Verified in native flows and tests | Native purchase verifies one free plus two distinct Plus sessions. fdebec3 Together verifies joining, shared links, media recovery and history do not recharge. Profile network 36055097185 retains the original quota ledger across a real outage and reconnect |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | Fresh 48e5a65 five-viewport journey 36068920060 passes 20 steps per profile; nine selected original screens are reviewed. 29eafe2 normal-release phone fullscreen passes and selected original PNGs are reviewed; its tablet observer times out before fullscreen. Prior 6e46041 phone/tablet fullscreen evidence is retained. 9a3fc05 native Together verifies complete player/reaction bounds with tablet keyboard inset. Final film motion and physical checks remain open; the SDK candidate is unadopted |
| 12 | Reliable Cast or exact blocker and fallback | Partial | Android sender and same-room handoff are implemented. Actual receiver acceptance awaits hardware; phone playback fallback is available |
| 13 | No placeholders, dead ends or silent failures | Partial | 6e46041 first-use/layout and purchase flows pass. 9a3fc05 Together verifies readable media errors, Choose another video recovery and shared-link confirmation. 5347142 makes same-source restoration visible and disables stale controls; native journey 36041063625 passes. Final-film inspection remains open |
| 14 | Clean-install full demo rehearsal | Partial | fdebec3 Together 36053642428 passes all 26 host and 25 guest stages on standard phone/tablet layouts. Profile network 36055097185 passes. The current 29eafe2 cohort has network, lifecycle, tablet-observer and midnight-assumption failures described below; it is not a clean rehearsal. The 98-second film has passed static sample review; full-motion acceptance remains open and prior candidates are retained |
| 15 | Shipaton submission confidence | Partial | Brand kit and original-size submission screenshot are prepared. Final under-two-minute film, full rehearsal, physical gates and remaining eligibility/legal checks remain open |

## Current verification

The `29eafe2` cohort passes hosted Check `36074183204` with 814 app tests,
87 Nearby tests and 14 platform tests. The original playback harness and Nearby
receipts are reviewed: API 35 decodes Bee and Sintel, and three processes retain
secure pairing identities, control authorization and revocation. Nearby remains
a same-emulator transport check, not physical Android-to-Windows acceptance.
Local-file run `36074182994` retains the actual DocumentsUI grant and restores
8,000 ms after process restart; its original restored-player PNG is reviewed.

The cohort also retains four failed scenarios, without treating retries as proof:

- Normal network `36074182939` passes radio loss, automatic pause and paused
  rejoin, then fails explicit replay convergence: two healthy native decoders
  still differ by about three seconds after 30 seconds. Sequential position
  reads differ by only milliseconds. The existing 0.90x correction cannot erase
  that buffered-start gap within the remaining window. A bounded local alignment
  against a stable, fresh room clock is under verification; room clocks are not
  independent measurements of the peer decoder. Independent review caught early
  consumption of the single correction opportunity when buffering cancelled the
  queued work. Cancellation now keeps that opportunity; an actual attempt or
  failed speed reset consumes it, and never emits a new room seek command.
- Decoder variant `36074171918` fails initial convergence before radios change.
  No native source error or fixture-cap release is exercised. The narrower
  failed-source rebuild criterion remains unaccepted.
- Lifecycle `36074183011` returns paused after HOME, but visible position moves
  from 51 to 58 seconds, exceeding the unchanged four-second tolerance. Existing
  evidence cannot separate command/observation latency from product pause latency.
  The runner now binds samples to their exact native capture and records device
  elapsed clocks around HOME within the original control budget. Its 78 mocked
  contracts pass locally; fresh native execution remains required. Two SDK Setup
  ANR dismissals in preparation also prevent clean-install acceptance for this run.
- Fullscreen `36074182951` passes the normal-release phone job. Three original
  PNGs show hidden controls, restored portrait playback and Home history; all
  three recording hashes match cloud-decoded originals. Motion/transition review
  remains open. The tablet job times out delivering an observer result before
  entering fullscreen; its failure PNG shows an unobscured playing app.

Together `36074183064` separately exposes an invalid fixed-day assertion: the
host plays before UTC midnight and the later free-allowance assertion expects
zero but receives one. This is consistent with the required new-day allowance;
the run ends before its ledger/date evidence is emitted, so it is not accepted.
The journey now validates the single charge's room/date and unchanged ledger,
then checks allowance against the real local dates bracketing each policy read.
It records midnight crossings instead of assuming a whole journey uses one day.
The guest's later driver disappearance and ADB offline state occur during failure
cleanup; the guard's SIGTERM receipt is not proof of an application ANR.

Hosted [Check 36073397389](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36073397389)
at `01d6106` passes **814 app, 87 Nearby and 14 platform tests**, formatting,
analysis, native observer SDK compilation, media contracts and the secret scan.
Eighteen source-recovery bridge regressions and
three native-platform contract tests cover paused source rebuilding, consecutive
outages, stale Play, new intent, cancellation, authorization and retained media
clocks. A two-socket-client regression verifies that a settled native interruption
pauses Together, suppresses a native auto-resume and accepts explicit Play again.
That regression does not establish Android focus delivery.

Review found that a ready, non-buffering native pause inside the three-second
remote-command echo window could remain unpublished if no later event arrived.
The bridge now rechecks the live snapshot at the end of that window and publishes
a sustained pause. New intent, source changes, native resume and disposal cancel
the pending check. Both the earlier settled-interruption socket case and a new
early-interruption case are retained, with controlled-clock cancellation tests.
Hosted Check `36072483614` at `9d3cd22` passes 813 tests but the new early
socket case fails: a paused heartbeat alone lets the next old room Play overwrite
the pause before the server receives it. The follow-up at `01d6106` signals one
local pause change through the existing Syncplay pending-change handshake.
Hosted Check `36073397389` passes both socket cases and all controlled-clock
cancellation cases at that follow-up. The original failure is retained.
An interruption that resumes entirely inside the echo window remains
indistinguishable from a delayed native echo with the current player API.

The current reconnection behavior protects fresh play intent for every accepted
source and playback target. Only a failed network source on a capable local
decoder gets one paused reopening within 30 seconds of TLS reconnection; healthy
controllers, local files and receivers are not rebuilt. A second real outage
resets the retry opportunity without permitting an old Play. Failed reopening
keeps the visible choose-video fallback. Ordinary notices expire after eight
seconds, while screen-reader navigation retains manual Dismiss.

Native failed-source recovery remains **unaccepted**. Debug `36062762988` first
proves radio loss, automatic pause and no-autoplay rejoin, then exposes a guest
HTTP decoder failure at 22,548 ms that cannot recover on explicit Play. That
failure motivated the current fix. The next run, `36066047985` at `f60c77a`,
stops before radio mutation: the independent Android observer returns
`root_missing` for 15 attempts within its eight-second capture budget. The
original screenshot shows an unobscured player; both window checks identify
MainActivity and the app PID is unchanged. No SDK Setup recovery occurs. This
isolates an observation failure before the network scenario, not an application
network result. The observer now adds one bounded, content-free accessibility
window diagnostic after a missing active root. A root query that times out keeps
known window metadata; no diagnostic can replace complete fresh XML and exact
app-window ownership. All 54 observer contracts pass. The observer/network/setup/
focus contract run passes 144 tests with one Windows platform skip. The new
interactive-window service flag still requires native acceptance; the helper's
independent compilation result follows below. No capture or caller deadline is extended.

The `48e5a65` native cohort exposes a helper compilation defect before affected
device scenarios can run: Android SDK stubs do not provide the Java lambda
bootstrap method used by the diagnostic thread. Install `36068920006`, lifecycle
`36068920009`, focus `36068920007`, network `36068920012` and fullscreen
`36068919999` fail this build step; they are not application-runtime failures.
Independent compiler run `36069747027` retains the exact `LambdaMetafactory`
error. The helper now uses an anonymous `Runnable`. Check adds an independent
SDK compile job and a focused `native_observer_only` dispatch so future helper
errors are caught without first building Flutter. Run `36069836038` at
`011da83` passes Java compilation, DEX, packaging, alignment, signing, signature
and manifest verification, plus observer contracts and the secret scan. Native
network `36069922387` passes at that corrected build. Its four original app
screenshots are unobscured; radio loss, automatic pause, paused rejoin, explicit
Play/Pause/Seek and unchanged quota pass. All four recording hashes match and
cloud decoding succeeds. The two native decoders keep their original identities,
so this run does **not** exercise failed-source reopening. Initial playback
converges in 26.148 seconds on this debug AVD; replay takes 1.535 seconds.
The 224 retained native-position records have no rejected or dropped entries.
No SDK Setup recovery occurs, and teardown/radio restoration succeed.

An explicit `decoder_failure` native variant is prepared to exercise the missing
failure path. After healthy native playback and real radio/socket loss, only the
guest seeks into a fixture region whose video keyframe and unserved byte ranges
are proved. The gate requires an error from the original Android controller,
one paused rebuild with a new ID, retained URI/clock, and an unchanged healthy
host. The task-owned fixture releases its prefetch cap by an identity-checked
local signal before radios return; release acknowledgement follows the actual
state change. This is a controlled cache miss during a real outage, not a claim
that radio loss alone always fails a decoder. Independent source review and 60
lightweight Python checks (one platform skip) are complete. Native evidence for
the variant is pending; the default healthy-network gate remains unchanged.

Focus `36069925181` stops before any focus-helper request: the observer reaches
`automation_start` but fails to connect to UiAutomation within its 20-second
startup budget. The original failure screenshot still shows an unobscured
playing Local screen, with app PID 3096 unchanged; both helpers are removed and
no SDK Setup recovery occurs. This is not a fresh focus acceptance result.

At `48e5a65`, five-viewport journey `36068920060` passes all 20 steps and saves
16 screenshots per profile. Nine selected original screens were inspected across
phone, small phone, landscape phone and both tablet orientations: first-use and
replay guides, source selection, home and the native sample film. Compact sheets
scroll above reachable actions; the landscape tablet has a separate invitation
column. These are display overrides on one API 35 AVD, not physical rotation.
Product matrix `36068920100` passes its two-device and two billing jobs on attempt
two after the first attempt's Android system-image archive download failed.
Production Together `36068920053` remains failed: both app logs reach their test
completion, but the guest driver then loses its VM-service connection with ADB
offline, and complete result receipts are absent. It is not accepted as a full
production journey or clean rehearsal.

Production purchase `36068920062` at `48e5a65` stops during the native
cancel/failure sequence because its second recording contains 64.564 seconds
against 70.003 seconds of measured coverage. The purchase journey is incomplete;
this is not accepted purchase evidence. The recorder now starts coverage only
after a bounded live MP4 probe observes a complete H.264 picture. A PID or MP4
header is insufficient. Startup stays bounded at 20 seconds, and readiness is
included in the existing 15-second rotation-gap limit. The three-second duration
tolerance and 90% journey coverage requirement are unchanged. All 102 purchase
and lifecycle recorder contracts pass locally without native tools or video
decoding. This repairs the coverage clock; it does not establish the cause of
the earlier encoded-duration shortfall.

Fresh production purchase `36071310593` at `6ad19ac` passes all 12 stages on a
clean API 35 MainApp install. Original result validation confirms native Test
Store cancel/failure/success, same-customer Restore after SDK cache invalidation,
one free and two distinct Plus rooms, both premium themes and a premium reaction
received by the real TLS peer. Six selected original screenshots were visually
inspected; all 12 required screenshots retain their native 1179x2556 dimensions.
Three 480x1040 recordings cover 199.514 of 206.491 measured seconds (96.621%),
with a largest rotation gap of 3.548 seconds. File hashes are retained. This is
one native player with a headless TLS peer, not two devices. Its runner checks
live picture readiness and ffprobe duration; strict whole-video decoding and
full-motion visual review are not established by this purchase run.

Previously accepted profile network `36055097185` at `0454176` uses one API 35
AVD with two real TLS clients and native decoders. Initial playback converges
in 7.561 seconds (4,551 / 4,183 ms), explicit replay in 5.531 seconds (39,733 /
40,459 ms). Automatic pause, no-autoplay rejoin, explicit Pause/Seek, unchanged
controllers/quota and cleanup pass. Original screenshots/windows are unobscured.
It predates staged radio restoration and paused source rebuilding; it does not
verify either change. A later internally green debug run with an SDK Setup ANR
over the app remains rejected as visual evidence.

The `fdebec3` native cohort passes normal API 29/35 debug and API 35 release clean
installation, playback, Nearby, five layout journeys, the runtime matrix,
lifecycle, fullscreen, Test Store purchase, same-customer RevenueCat relaunch/
expiry and SAF relaunch. Together `36053642428` passes **26 host and 25 guest
stages** on independent phone/tablet emulators, with settled positions matching
at 12,416, 53,361 and 55,242 ms. Compact capture preserves normal UI geometry and
uses one complete segment per device. Hosted review `36056723226` strictly
decodes both sources; all 95 PNG hashes match. Inspected originals show the full
tablet video/controls with keyboard, readable link confirmation and resumed
history. These are accepted builds, not current-head evidence for later changes.

Normal-release Local audio focus `36063562267` at `f56c8e8` passes both independent
Android focus cases with unchanged foreground PID 2770. Permanent loss pauses
within a measured 1,035 ms upper bound and holds 0:44 after release until explicit
Play. Transient loss pauses within 1,161 ms, holds 1:19, then resumes within
4,058 ms of release and advances without a Play tap. Bounds include complete UI
observation. Original UI/AudioService records establish actual focus ownership,
no Activity pause/stop, no observation timeout and no SDK Setup recovery. Both
helpers are removed. All three recording hashes match; cloud decoding confirms
47.437/51.449/42.673-second streams and new post-roll pictures. Physical hardware
and Together-room Android focus remain separate gates.

The **98-second film candidate** passes hosted render `36059267954` at `4dfd3e0`:
2,940 frames strictly decode, seven native source pins match and the EDL matches
the repository. SHA-256:
`5ced046aacf9f55a9b8be9344e27fd3a3266056c298e712ef2ce2b971d5c92c4`.
All 42 shot-boundary PNGs have verified hashes and were visually inspected. All
25 periodic samples were inspected or exactly match previously reviewed images.
Appearance ends on the applied theme and the last native cut ends in the second
Plus room. Loading and held frames remain; **full-motion acceptance stays open**.
Later source recovery is not represented as present in the pinned clips.

[Acceptance history](ACCEPTANCE_HISTORY.md#archived-september-25-recovery-investigations-through-5ea2aa2)
retains original failures, earlier candidates and investigation details. The
normal app uses unmodified Flutter 3.44.0 / Dart 3.12.0. Heavy verification and
video decoding run in hosted CI; local review uses static PNGs and metadata.

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

At September 24 22:34 UTC the current bounded two-fps recorder has about 166 MB
persisted. The latest scoped resource check finds about 10.2 GiB free RAM and no
local Dart, Java, FFmpeg or Android emulator. The selected image is a single
static phone/tablet frame from the reviewed 100-second film candidate; it is
labelled captured evidence, not live Android. Historical recording gaps below
remain part of the record.

Following two reported machine freezes, local heavy work is serialized and
Android builds, emulator runs and full regression suites use hosted CI. No
Flutter, Gradle or emulator process was running at the September 24 10:20 UTC
inspection; roughly 10 GiB RAM was free. This does not establish the cause of
the earlier freezes. One reviewer handles bounded observer diagnostics and mocked
contracts; no local Android compilation or emulator is used.

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
