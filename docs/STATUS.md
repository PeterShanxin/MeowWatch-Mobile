# Delivery status

Last updated: 2026-09-25 (Asia/Shanghai). **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Verified on emulators | 29eafe2 passes normal API 29/35 debug and API 35 release clean install in hosted run 36074182955. The original normal-release APK hash, clean-install receipt, first-use and shared-video screens are reviewed. These are normal lib/main.dart APKs; release is debug-signed with billing disabled. Physical-device acceptance remains separate |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public AGPL-3.0 repository. Hosted Check 36083540519 at a4b8107 passes the secret scan, formatting, analysis, 828 app tests, Nearby/platform contracts and independent native observer SDK compilation. Final artifacts and repository closeout remain open |
| 3 | Clear first-launch create/join | Verified on emulators | 6e46041 passes all five first-use/layout journeys. Fresh 9a3fc05 Together 36037966143 passes actual Start, invitation review and Join on independently running phone/tablet emulators |
| 4 | Two real clients repeatedly play/pause/seek in sync | Partial | 6daa1ea Together 36078687173 passes 26 host and 25 guest stages on independent phone/tablet emulators. Settled positions match at 14,541, 53,361 and 55,374 ms. Normal network 36080635480 passes at 4c01143 with real radio loss, paused rejoin and explicit Play/Pause/Seek after the self-clock catch-up fix. Failed-source rebuilding remains unaccepted. Position agreement does not establish identical decoded frames or physical hardware |
| 5 | Real-session chat/reactions/presence | Verified on two emulators | 9a3fc05 passes repeated real-keyboard chat, presence, confirmed peer links and actual player/reaction viewport bounds. 6e46041 Test Store journey verifies a premium reaction received by a real TLS peer |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | 6daa1ea normal-release lifecycle 36078684061 passes HOME pause, no-autoplay return, new-process restoration and explicit replay; original receipts and selected screens are reviewed. Normal-release Local Mode audio focus 36074183098 passes. Together focus 36084442812 reaches both native interruptions but detects transient-focus autoplay; this gate fails. Normal network 36080635480 passes at 4c01143; failed-source rebuilding, Together audio focus and physical interruption acceptance remain open |
| 7 | Local Mode and Continue Watching | Partial | 6e46041 normal lifecycle restores 45 seconds in a new process without autoplay. Fresh 29eafe2 SAF relaunch 36074182994 retains the real content grant and restores 8 seconds; the original restored-player screenshot is reviewed. The same-source history restoration fix at 5347142 passes unit/widget checks and the standard-layout native journey 36041063625. Physical playback acceptance remains open |
| 8 | Secure phone-to-desktop discovery/pair/control | Partial | Fresh 29eafe2 Android Nearby 36074183032 passes pinned TLS pairing/control/revocation and protected persistence across three processes on one emulator. Desktop f5a9103 clean Release builds and its actual Windows UI was inspected; dba4b57 updates its dependency pin and passes hosted Windows CI and 1,494 tests. Physical Android-to-Windows discovery/pair/control/revoke/restart proof remains open |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | Fresh 29eafe2 production Test Store 36074182983 passes 12 stages, one free and two Plus hosts, native cancellation/failure/success, a premium reaction and same-customer Restore after cache invalidation. Original receipts and three selected screens are reviewed. Same-customer relaunch/expiry 36074183058 also passes at 29eafe2. Physical and Play-production evidence remain separate; the earlier anomalous Restore result remains historical and unexplained |
| 10 | Correct daily quota and session continuity | Verified in native flows and tests | Native purchase verifies one free plus two distinct Plus sessions. 6daa1ea Together 36078687173 verifies joining, shared links, media recovery and history do not recharge, then charges the guest's new hosted room once. Real local dates bracket policy reads; this native run does not cross midnight. Four unit cases cover midnight. Profile network 36055097185 retains the original ledger across an outage and reconnect |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | 48e5a65 five-viewport journey 36068920060 passes 20 steps per profile; nine selected original screens are reviewed. 6daa1ea normal-release fullscreen 36078690609 passes phone and tablet: hidden controls/system bars, orientation restoration and two-stage Back. Five selected original fullscreen/return screens and six Together screens are reviewed. Final film motion and physical checks remain open; the SDK candidate is unadopted |
| 12 | Reliable Cast or exact blocker and fallback | Partial | Android sender and same-room handoff are implemented. Actual receiver acceptance awaits hardware; phone playback fallback is available |
| 13 | No placeholders, dead ends or silent failures | Partial | 6e46041 first-use/layout and purchase flows pass. 9a3fc05 Together verifies readable media errors, Choose another video recovery and shared-link confirmation. 5347142 makes same-source restoration visible and disables stale controls; native journey 36041063625 passes. Final-film inspection remains open |
| 14 | Clean-install full demo rehearsal | Partial | 6daa1ea Together 36078687173 passes all 26 host and 25 guest stages on standard phone/tablet layouts without SDK Setup ANR repair. Normal-release lifecycle and both fullscreen layouts also pass. Normal network 36080635480 also passes at 4c01143. Failed-source rebuilding and Together-focus acceptance remain open, so this is not a complete rehearsal. The 98-second film has passed static sample review; full-motion acceptance remains open |
| 15 | Shipaton submission confidence | Partial | Brand kit and original-size submission screenshot are prepared. Final under-two-minute film, full rehearsal, physical gates and remaining eligibility/legal checks remain open |

## Current verification

The `29eafe2` cohort passes hosted Check `36074183204` with 814 app tests,
87 Nearby tests and 14 platform tests. The original playback harness and Nearby
receipts are reviewed: API 35 decodes Bee and Sintel, and three processes retain
secure pairing identities, control authorization and revocation. Nearby remains
a same-emulator transport check, not physical Android-to-Windows acceptance.
Local-file run `36074182994` retains the actual DocumentsUI grant and restores
8,000 ms after process restart; its original restored-player PNG is reviewed.
Production purchase `36074182983` passes all 12 stages, native cancellation,
failure/success, same-customer Restore and two Plus rooms; three original screens
are reviewed. Its native recording coverage is 96.796% with a 3.599-second largest
gap, not uninterrupted footage or full-motion acceptance. Test Store relaunch
`36074183058` preserves the same customer across different processes and observes
real expiry followed by inactive Restore. Foreground audio focus `36074183098`
passes on normal-release Local Mode: permanent pause upper bound 1,600 ms,
transient pause 2,513 ms, and transient resume 5,268 ms. Three original screens
and recording hashes are reviewed; this does not establish Together-room focus
delivery or physical-device behavior.

Normal-install `36074182955` passes API 29/35 debug and API 35 release at
`29eafe2`. The original release receipt and APK hash are reviewed: one launch,
no SDK Setup repair, no fatal app log, normal `lib/main.dart`, and a non-debuggable
API 35 process. It is signed with the Android debug key and billing is disabled.
Seven cold/warm incoming-media and invitation cases retain explicit confirmation
and cancel without replay. Confirmed HTTPS and temporary read-only content-URI
playback advance five and four seconds. First-use, shared-file confirmation and
actual playback PNGs are reviewed; this is not physical or full-motion evidence.

Check `36078119317` at `6daa1ea` passes all 824 app tests, 87 Nearby tests,
14 platform tests, formatting, analysis, native observer SDK compilation and
media/secret checks. This includes four new midnight quota tests and six bounded
calibration regressions. The preceding Check `36077388034` at `0ab6f1f` retained
two calibration timeouts and 822 passing app tests. The fix commits speed-reset
success/failure state inside the queued native command, before a following
calibration can inspect it; an already reported reset error is not reported
again. Both previously failing cases now pass. The subsequent Android results
below separately establish the accepted native behavior.

The targeted `6daa1ea` cohort now has fresh accepted native evidence:

- Lifecycle `36078684061` uses normal-release MainApp on API 35. HOME changes
  the last visible clock from 38 to 41 seconds, within the unchanged four-second
  tolerance; the 9.288-second hold and foreground return remain paused. A new
  process restores 58 seconds without autoplay, then explicit Play advances ten
  seconds. No SDK Setup ANR repair occurs. The HOME command is bracketed by
  device clocks 410 ms apart; this does not measure the app's internal callback.
- Fullscreen `36078690609` passes normal-release phone and tablet. Actual video
  advances in fullscreen, controls and system bars hide, first Back restores
  the same paused source and orientation, and second Back returns Home. All six
  recording hashes match the cloud-decoded originals. Five original PNGs are
  reviewed; full-motion inspection remains open.
- Together `36078687173` passes 26 host and 25 guest steps across two independent
  API 35 emulators. Three settled two-way control positions match at 14,541,
  53,361 and 55,374 ms. Chat, reactions, confirmed peer links, readable media
  errors, recovery, history and a new movie night pass with unchanged/one-time
  quota charges as appropriate. Neither emulator needs SDK Setup ANR repair.
  Six original PNGs are reviewed; four original recording segments, their timing
  files and the framed output match the runner manifest. Recording gaps remain
  visible (largest 1.785 seconds); full motion is not reviewed.

Normal network `36078681672` fails initial playback convergence before radio
loss. Its host first follows the guest backwards, then repeatedly catches up to
its own server-projected clock while buffering. Native position reads succeed;
the actual decoder/resource contribution is not isolated by those reads. The
bounded calibration fallback is not reached in this run. `4c01143` excludes
self-origin room heartbeats from startup catch-up while permitting a fresh
remote setter to take over. Hosted Check `36080633060` passes 827 app tests,
including three self/remote transition regressions. Native network `36080635480`
now passes at that commit: actual radio loss pauses both decoders, rejoin keeps
the same room/media/quota paused, and explicit Play/Pause/Seek converges. Initial
playback takes 16.154 seconds and replay 22.328 seconds to meet the unchanged
one-second position gate on this debug AVD. These are not instant-resume or
physical-device measurements. All 372 native-position records are retained
without rejection/drop; no SDK Setup repair occurs. Four original PNGs are
reviewed and all four recording hashes match their cloud-decoded originals.
Both healthy controllers retain their IDs, so failed-source rebuilding is still
unaccepted. The controlled variant `36081703062` passes initial convergence,
then fails its fixture-byte guard after radios are disabled. The guard currently
rejects every artificial-cap wait, including waits following the intended
offline seek. Existing wait records lack timestamps, so they cannot establish
whether the first cap was reached before or after radio loss. This failed run
does not accept the decoder-rebuild path. The repaired guard now requires a
same-process checkpoint after the real socket failure and automatic pause,
immediately before the seek. Same-host monotonic timestamps distinguish early
cap waits from allowed post-proof waits, including late-written records and
interleaved request threads. Every pre-release served byte must stay below the
proved keyframe cap; the original native error remains required. The server pace
is 160 KiB/s. Independent source review finds no remaining defect; 65 lightweight
contracts pass with one Windows-inapplicable skip. Fresh native acceptance is
still required.

The corrected failed-decoder run `36084305883` at `c16b53a` passes initial
native convergence, then fails the native UI capture before any radio-disable
action. The app PID remains unchanged and MainActivity is focused and
unobscured. Fourteen root queries return no root; the fifteenth obtains one
after 2.535 seconds, then `root.refresh()` does not complete within the fixed
capture budget. System contention and skipped frames are observed, but the
unique cause is not established. The observer now streams its already computed,
bounded first-missing-root diagnostic immediately, preserving it even if a later
framework call blocks. This adds no retry, changes no deadline, and cannot
replace complete hierarchy acceptance. Mocked observer contracts pass; SDK
compilation and a fresh native run remain required.

The new Together-room audio-focus journey uses MainApp with one API 35 native
decoder and an independent real TLS client in the same process. It continuously
checks for native/room autoplay between focus loss and explicit Play. Its first
run `36079974766` fails named-AVD ownership checks during environment preparation
and rejects a successful streamed helper installation, before app acceptance.
The runner now uses the existing interruption AVD naming policy and shared
installation-result parser; 35 lightweight contracts pass. Run `36081445086`
then reaches real TLS and native playback, but its first stage receives HTTP 400:
the strict bridge requires a bounded Content-Length and the Dart sender omitted
it. No native focus request occurs. The sender now sets the exact UTF-8 body
length. Hosted Check `36083540519` at `a4b8107` passes 828 app tests, including
the real HTTP sender/server regression. Native run `36083537904` fails earlier
while the media-sheet keyboard is changing: its fixed-delay tap finds no
hit-testable Use this link button. No focus request occurs. The journey now
reuses the verified text-entry helper and waits for the actual hit-testable
control instead of a fixed 450 ms delay. This is separate from the accepted
normal-release Local Mode focus evidence.

Together focus `36084442812` at `60543ff` now exercises both interruptions with
the same API 35 app PID and all four native UI captures. Permanent focus loss
pauses within a 2,589 ms upper bound and remains paused until explicit Play.
Transient loss pauses within 2,954 ms, but the continuous listener records a
native playing event after focus returns, before the bridge pauses again. The
release screenshot is paused and alone would miss the defect. This is a failed
gate, not accepted Together focus behavior; the retained native play request
must be cleared before focus returns. Its TLS peer shares the app process and
is not evidence from a second physical device.

The local machine remains limited to source edits, lightweight evidence reads
and the bounded two-frame-per-second static showcase recording. Builds,
emulators and video processing run only in GitHub Actions.

Earlier failed network, lifecycle, fullscreen and purchase runs remain in the
[interruption investigation history](ACCEPTANCE_HISTORY.md#archived-september-25-interruption-investigations-through-60543ff).
Their original failures and runtime limits are preserved. The current source
retains one paused reopening for a failed local network decoder; healthy
controllers, local files and receivers are not rebuilt. Fresh explicit Play
is required after reconnect, and failed reopening keeps Choose another video.

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

At September 25 00:44 UTC the current bounded two-fps recorder has about 187 MiB
persisted and is still saving chunks. The latest scoped resource check finds
about 10.2 GiB free RAM, a 29 MiB BelowNormal showcase service, and no local Dart,
Java, FFmpeg or Android emulator. The selected image is a single
static phone/tablet frame from the reviewed 100-second film candidate; it is
labelled captured evidence, not live Android. Historical recording gaps below
remain part of the record.

Following two reported machine freezes, local heavy work is disabled. Android
builds, emulator runs, full regression suites and video processing use hosted CI. No
Flutter, Gradle or emulator process was running at the September 24 10:20 UTC
inspection; roughly 10 GiB RAM was free. This does not establish the cause of
the earlier freezes. Agent assignments are bounded source work and lightweight
mocked contracts; no local Android compilation or emulator is used.

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
