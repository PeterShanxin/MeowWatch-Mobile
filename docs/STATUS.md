# Delivery status

Last updated: 2026-09-25 (Asia/Shanghai). **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Verified on emulators | fdebec3 passes normal API 29/35 debug and API 35 release clean install in hosted run 36044617989. These are normal lib/main.dart APKs. Physical-device acceptance remains separate |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public AGPL-3.0 repository. Hosted Check 36067406288 at 5ea2aa2 passes the secret scan, formatting, analysis, 807 app tests, 87 Nearby tests and 14 platform tests. Final artifacts and repository closeout remain open |
| 3 | Clear first-launch create/join | Verified on emulators | 6e46041 passes all five first-use/layout journeys. Fresh 9a3fc05 Together 36037966143 passes actual Start, invitation review and Join on independently running phone/tablet emulators |
| 4 | Two real clients repeatedly play/pause/seek in sync | Verified on two emulators; failed-source recovery follow-up open | fdebec3 Together 36053642428 passes all 26 host and 25 guest stages with repeated two-way controls. Settled native positions match at 12,416, 53,361 and 55,242 ms. Profile network 36055097185 passes at 0454176. Debug network 36062762988 reveals a decoder source failure during the outage; its paused recovery fix is being verified. Position agreement does not establish identical decoded frames or physical hardware |
| 5 | Real-session chat/reactions/presence | Verified on two emulators | 9a3fc05 passes repeated real-keyboard chat, presence, confirmed peer links and actual player/reaction viewport bounds. 6e46041 Test Store journey verifies a premium reaction received by a real TLS peer |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | Normal release lifecycle passes at fdebec3; permanent and transient foreground audio focus pass in 36063562267 at f56c8e8 with original UI/AudioService evidence. Profile network 36055097185 at 0454176 passes real radio loss, automatic pause, no-autoplay rejoin and explicit replay/Pause/Seek. The current debug gate enforces unobscured MainApp ownership and exposes a failed network decoder that needs paused source rebuilding. Physical and Together-room transient-focus acceptance remain open |
| 7 | Local Mode and Continue Watching | Partial | 6e46041 normal lifecycle restores 45 seconds in a new process without autoplay. 56fcd32 SAF relaunch 36039255967 retains the real content grant and restores 8 seconds. The same-source history restoration fix at 5347142 passes unit/widget checks and the standard-layout native journey 36041063625. Physical playback acceptance remains open |
| 8 | Secure phone-to-desktop discovery/pair/control | Partial | 6e46041 Android Nearby 36037410146 passes real pinned TLS pairing/control/revocation and protected persistence. Desktop f5a9103 clean Release builds and its actual Windows UI was inspected; dba4b57 updates its dependency pin and passes hosted Windows CI and 1,494 tests. Physical Android-to-Windows discovery/pair/control/revoke/restart proof remains open |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | 6e46041 production Test Store 36037410075 passes 12 stages, one free and two Plus hosts, native cancellation/failure/success, a premium reaction and same-customer Restore. Same-customer relaunch/expiry 36037410042 passes. Physical and Play-production evidence remain separate; the earlier anomalous Restore result remains historical and unexplained |
| 10 | Correct daily quota and session continuity | Verified in native flows and tests | Native purchase verifies one free plus two distinct Plus sessions. fdebec3 Together verifies joining, shared links, media recovery and history do not recharge. Profile network 36055097185 retains the original quota ledger across a real outage and reconnect |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | 6e46041 passes five viewport journeys and normal-release phone/tablet fullscreen. 9a3fc05 native Together verifies complete player/reaction bounds with tablet keyboard inset; original frame review shows the full heart and video. Source frame hashes are verified in hosted reviews. Final film motion and physical checks remain open; the SDK candidate is unadopted |
| 12 | Reliable Cast or exact blocker and fallback | Partial | Android sender and same-room handoff are implemented. Actual receiver acceptance awaits hardware; phone playback fallback is available |
| 13 | No placeholders, dead ends or silent failures | Partial | 6e46041 first-use/layout and purchase flows pass. 9a3fc05 Together verifies readable media errors, Choose another video recovery and shared-link confirmation. 5347142 makes same-source restoration visible and disables stale controls; native journey 36041063625 passes. Final-film inspection remains open |
| 14 | Clean-install full demo rehearsal | Partial | fdebec3 Together 36053642428 passes all 26 host and 25 guest stages on standard phone/tablet layouts. Profile network 36055097185 passes. The debug failed-source recovery remains under verification. The 98-second film has passed static sample review; full-motion acceptance remains open and prior candidates are retained |
| 15 | Shipaton submission confidence | Partial | Brand kit and original-size submission screenshot are prepared. Final under-two-minute film, full rehearsal, physical gates and remaining eligibility/legal checks remain open |

## Current verification

Hosted [Check 36067406288](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36067406288)
at `5ea2aa2` passes **807 app, 87 Nearby and 14 platform tests**, formatting,
analysis, media contracts and the secret scan. Eighteen bridge regressions and
three native-platform contract tests cover paused source rebuilding, consecutive
outages, stale Play, new intent, cancellation, authorization and retained media
clocks. A two-socket-client regression verifies that a settled native interruption
pauses Together, suppresses a native auto-resume and accepts explicit Play again.
That regression does not establish Android focus delivery.

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
interactive-window service flag and helper still require cloud compilation and
native acceptance; no capture or caller deadline is extended.

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
