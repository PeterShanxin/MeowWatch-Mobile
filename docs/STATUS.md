# Delivery status

Last updated: 2026-09-25 (Asia/Shanghai). **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Verified on emulators | f16b148 passes normal API 29/35 debug and API 35 release clean install in hosted run 36029407625. These are normal lib/main.dart APKs. Physical-device acceptance remains separate |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public AGPL-3.0 repository. The 60aab38 snapshot passes hosted Gitleaks 8.30.1 with zero findings in 540 tracked files and 149 fetched commits; no suspicious tracked paths. Final artifacts and repository closeout remain open |
| 3 | Clear first-launch create/join | Verified on emulators | f16b148 passes all five first-use/layout journeys. Fresh 9a4e29c Together 36031293517 passes actual Start, invitation review and Join on independently running phone/tablet emulators |
| 4 | Two real clients repeatedly play/pause/seek in sync | Verified on two emulators | 9a4e29c Together passes repeated two-way controls, shared-media recovery and another room. Native settled positions match at 10,086 ms, 53,361 ms and 54,704 ms. This establishes position convergence, not identical decoded frames or physical hardware |
| 5 | Real-session chat/reactions/presence | Verified on two emulators | 9a4e29c passes presence, repeated chat with the real Android keyboard, reactions and confirmed peer-link playback. f16b148 purchase also proves a premium reaction received by a real TLS peer |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | f16b148 release lifecycle 36029407933, foreground audio focus 36029408003 and debug network 36029407709 pass; ff8a559 profile network also passes. No autoplay, explicit replay and process-restart history are verified on API 35. Physical and transient-focus acceptance remain open |
| 7 | Local Mode and Continue Watching | Partial | f16b148 normal lifecycle restores 56 seconds in a new process, then advances on explicit Play. Five layout journeys and SAF relaunch pass. 9a4e29c Together resumes the original room without another host charge. Physical playback acceptance remains open |
| 8 | Secure phone-to-desktop discovery/pair/control | Partial | 773d41e Android Nearby passes real pinned TLS pairing/control/revocation and protected persistence across three process runs. Desktop f5a9103 clean Release builds and its actual Windows UI was inspected; dba4b57 updates its dependency pin and passes hosted Windows CI and 1,494 tests. Physical Android-to-Windows discovery/pair/control/revoke/restart proof remains open |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | f16b148 production Test Store 36029407726 passes 12 stages, one free and two paid hosts, native cancellation/failure/success and same-customer Restore. Same-customer relaunch/expiry 36029407732 also passes. Physical and Play-production evidence remain separate; the earlier anomalous Restore result remains historical and unexplained |
| 10 | Correct daily quota and session continuity | Verified in native flows and tests | f16b148 hosting matrix and purchase pass one free plus two distinct Plus sessions. Network recovery preserves the ledger. 9a4e29c Together verifies shared links, media recovery and history do not recharge; a new room consumes the new host allowance while joining stays free |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | f16b148 passes all five viewports and normal-release phone/tablet fullscreen. Prior full 80-image layout review is retained; fresh original fullscreen frames show hidden bars/controls and correct Home history. 9a4e29c proves keyboard focus/bounds and repeated chat. Final film motion and physical checks remain open; the SDK candidate is unadopted |
| 12 | Reliable Cast or exact blocker and fallback | Partial | Android sender and same-room handoff are implemented. Actual receiver acceptance awaits hardware; phone playback fallback is available |
| 13 | No placeholders, dead ends or silent failures | Partial | f16b148 first-use/layout and purchase flows pass. 9a4e29c Together verifies readable media errors, Choose another video recovery, shared-link confirmation and resumed room history. Fresh final-film inspection remains open |
| 14 | Clean-install full demo rehearsal | Partial | f16b148 native cohort passes apart from the reproduced Together test-input cache issue; the corrected 9a4e29c full phone/tablet journey passes all 26 host and 25 guest stages. A fresh 104-second candidate combines the same app implementation, with different test drivers and debug/release runtimes disclosed. Film and physical acceptance remain open |
| 15 | Shipaton submission confidence | Partial | Brand kit and original-size submission screenshot are prepared. Final under-two-minute film, full rehearsal, physical gates and remaining eligibility/legal checks remain open |

## Current verification

The tablet stage at `6e46041` now fits the available viewport, including the
keyboard inset; decorative reactions keep their spoken label and fit within
that stage at large text sizes. Native bounds checks cover the real player and
reaction. Independent review found a test race between sending a reaction and
the server echo; `9a3fc05` waits for that echo before checking its bounds. It
also removes an unrelated offscreen-title expectation exposed by Check
`36037410520`. Corrected hosted Check `36037961937` passes 776 app, 87 Nearby
and 14 platform tests, formatting, analysis and the secret scan; the fresh native
cohort and recording-display Together `36037966143` remain in progress. The
purchase driver now keeps rendering during asynchronous waits. Fresh footage
is required before replacing the reviewed candidate below.

The 104-second candidate at `8986850` renders and strictly decodes all 3,120
frames in hosted run `36035397960`; its SHA-256 is
`d6fab4dd025df6643143205c834a92c59314ecc5f0f1d9e658175035f69b2e03`.
All 26 exported samples are inspected: captions and framing remain outside app
pixels, but the actual tablet video stage clips its lower reaction and becomes
a cropped strip above the keyboard. This is a rendered product defect requiring
a layout fix and fresh native proof. The film remains a review candidate;
full-motion acceptance, physical checks and publication remain open.

The fresh `f16b148` PR cohort passes normal API 29/35 debug and API 35 release
install, native playback, local-file relaunch, Nearby, purchase, RevenueCat
relaunch/expiry, the runtime matrix, five layout journeys, lifecycle, foreground
audio focus and debug network recovery. Fullscreen tablet passes; phone attempt
one fails while downloading the Android system image (`ZipFile unknown archive`),
before launching any emulator or application. Only that failed job is retried;
the phone's second attempt passes the unchanged native gate.
Standard-display Together `36029407646` reproduces the same second-entry test
focus failure as the recording-display run below. The corrected recording-display
Together `36031293517` at `9a4e29c` passes all 26 host and 25 guest stages,
including repeated chat with real keyboard focus/bounds, shared links, media
recovery, history and a fresh room. Hosted original-frame review `36033311843`
strictly decodes both recordings; two source and 18 PNG hashes match. The phone
records 1,407 pictures over 126.236 seconds; tablet 1,386 over 127.486 seconds.
There is no claim of inter-device frame alignment or full film motion acceptance.

Fresh receipts at that build show lifecycle `36029407933` restoring 56 seconds
in a new process (3025 → 5921), with no autoplay and explicit native advancement.
Focus `36029408003` completes the paused hierarchy within 1,279 ms of the native
request; PID 2954 remains foreground and playback stays at 52 seconds through
release until explicit Play. Debug network `36029407709` reconnects without
autoplay and explicit replay converges in 3.872 seconds at 45,932 / 45,889 native
ms; media, both controllers and the free-host ledger are preserved. Both focus
helpers are removed and network peer/teardown errors are empty. These remain
API 35 x86_64 emulator results, separate from physical acceptance.

Purchase `36029407726` passes all 12 native Test Store stages, same-customer
Restore, the premium reaction and two distinct Plus rooms. Hosted extraction
`36030948296` strictly decodes its two originals; both source hashes and all 36
PNG hashes match. Selected original frames show the actual SDK dialog, active
Plus, Restore feedback and both appearances. The 1.231-second recording gap is
retained. These sampled frames do not establish complete final-film motion
acceptance. Hosted Check `36031826072` at `25fa5dc` passes 775 app, 87 Nearby and
14 platform tests, analysis, formatting, media contracts and the secret audit.
The new repeated-entry regression keeps the test IME unregistered from its first
input, matching the native binding's missing cache-reset callback.

The `3a0307f` PR cohort passes Check, normal install, native playback,
local-file relaunch, Nearby, RevenueCat process relaunch, purchase, runtime
matrix and debug radio loss/recovery. Check scans its actual PR merge checkout
`4c260086`: 536 tracked files and 135 fetched commits, zero Gitleaks findings.
Manual recording-display Together `36020865442` also passes; original footage
and fresh purchase `36021221637` have passed hosted extraction/full decode in
`36023313899` / `36023318162`. All 18 Together and 31 purchase extracted PNG
hashes match. Selected original purchase frames show the real Test Store flow,
active Plus appearance and paid rooms. Original tablet frame review exposed a
real keyboard issue: opening chat reduced the body height enough to select the
video-only landscape layout. `ff8a559` classifies the layout using height before
keyboard reduction while retaining the resized body; the widget regression
proves draft, focus and Send remain above the keyboard. The native two-device
driver now requires the actual keyboard inset and visible focused composer.
Fresh Together `36025427753` reaches the keyboard/composer bounds checks but
fails the focused-field assertion before Send. The host subsequently times out
waiting for that unsent message. `09d0c1d` fixes the remaining cause: an inserted
typing-indicator Padding replaced the unkeyed composer Padding, disposing its
text-field state. A stable composer key preserves focus/draft, and ChatStore
excludes only the current assigned username's own typing echo. Independent
review found no blocking issue. Peer typing insertion/removal and username
reassignment regressions pass in hosted Check `36028137405`: 773 app, 87 Nearby
and 14 platform tests, analysis, media contracts and secret audit. A fresh
two-device recording `36028173522` confirms the first chat now retains focus,
then fails before sending a second link: the test input helper reads an empty
field. Flutter's `showKeyboard` caches the last EditableTextState and does not
request focus again for the same retained composer after explicit unfocus. The
real integration binding does not install the test IME callback that clears
that cache. The helper now explicitly requests the keyboard before injection;
debug/profile regressions retain the cached state with the test IME unregistered.
Native verification passes in `36031293517`. This changes test input only, not the app's
composer or quota assertions. Earlier footage is not the final submission film.

The same cohort fails normal lifecycle and focus interruption with observed
paused positions of 54 seconds versus a 49-second pre-action snapshot. These
receipts include time spent returning the hierarchy and issuing the action;
they do not isolate the product's pause latency. Fullscreen phone/tablet fail
after one reveal touch when the returned tree still lacks controls. The runner
now polls for the new tree within the original 35-second action budget, without
repeating the touch; two regressions and 47 fullscreen contracts pass. Lifecycle
and focus AVDs now use a 540x1200 framebuffer at 210 dpi, preserving the prior
1080x2400-at-420-dpi layout. Only verified, task-named AVDs may be prepared;
before/after configuration is retained. With unchanged assertions, normal
release lifecycle `36024427344` at `7cf42de` passes: real HOME, 43-to-46-second
pause, no autoplay, explicit replay and 63-second history restoration in a new
app process. Fullscreen `36024422678` passes on phone and tablet: same-process
native advancement, system bars/orientation, reveal controls and Back behavior.
Hosted review `36027358617` strictly decodes their six original segments. All
six source hashes and 33 extracted PNG hashes match; selected original phone
and tablet frames show immersive video with hidden controls/bars and returned
Home with matching history. This sampled review does not claim complete motion
acceptance of the final film.

Focus `36024431409` still fails the former displayed-position check (40 to 45).
Its pre-action snapshot precedes the native focus request by 5.502 seconds;
AudioService records application focus abandonment 97 ms after the helper
request. Neither fact establishes an exact decoder pause time. `d07841e` uses
the helper's elapsed-realtime timestamp immediately before requesting focus
and the complete paused hierarchy's timestamp after traversal. The same-device
ordering, XML hash and application PID must match, with completion within the
unchanged 4,000 ms limit. Position rewind, foreground/history changes, unstable
pause and autoplay still fail. This is a conservative observed-response bound;
a slow observer cannot prove the deadline, and the pre-request snapshot cannot
fully exclude an unrelated spontaneous pause. Both observer and helper protocol
versions advance, with 73 local lightweight contracts passing. Fresh normal
release run `36027348723` passes on API 35 x86_64 at `d07841e`: the complete
paused hierarchy arrives within 1,706 device-clock ms of request start. App PID
2907 remains foreground with no Activity pause/stop; position stays at 47
seconds through focus hold, release and no-autoplay checks, then explicit Play
advances to 65 seconds. Both owned helpers are removed. The failed originals
remain retained; GSM/transient focus and physical audio are not established.

Profile network `36021989188` successfully disables/restores both radios and
reconnects without autoplay, but explicit replay fails convergence: after
30.353 seconds the native positions are 59,893 / 57,864 ms. Both players are
playing and no native error is reported. The log records repeated 0.95/1.0
rate changes around buffering; the direction of causation is not established.
`e54be35` retains the original correction budget across transient buffering,
restores 1x immediately and requires stable ready playback plus a fresh advancing
heartbeat before slowing again. Fresh profile network `36025432329` at
`ff8a559` passes: initial convergence in 7.052 seconds (4,650 / 3,934 native ms),
then real radio loss, no-autoplay reconnect and explicit replay convergence in
10.448 seconds (45,488 / 44,639 ms). Both are within the unchanged one-second
position / 30-second recovery limits. The same room, media, controller identities
and quota ledger survive; peer and teardown errors are empty. This runtime is
one API 35 emulator with two real TLS clients and Android decoders, only the host
rendered. It does not replace the independent two-device journey or hardware
acceptance. All owned radios/helpers/recorders are restored or removed.

Hosted Check `36025421802` at `ff8a559` passes 771 app tests, static analysis,
portable Nearby/platform tests, media contracts and the secret audit. No local
Flutter build, emulator or video processing is used during this low-load phase.

The prior TLS, startup synchronization, fullscreen, installation, billing and
rendered-layout investigations are retained in
[Acceptance history](ACCEPTANCE_HISTORY.md#archived-september-25-verification-details-through-the-3a0307f-cohort).
Historical failures and unadopted SDK experiments are not erased or promoted to
current acceptance. The normal app uses unmodified Flutter 3.44.0 / Dart 3.12.0.
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
