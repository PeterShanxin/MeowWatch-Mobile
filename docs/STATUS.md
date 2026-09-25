# Delivery status

Last updated: 2026-09-25 (Asia/Shanghai). **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Delivery closeout order

On September 25 the owner directed delivery closeout. Finish the failed-decoder
network recovery check, then freeze product changes except demo-blocking defects
or security issues. Use the existing checks to prepare the final installable
build, rehearse the complete first-install demo, finish the film under two
minutes, and finalize the public repository and submission materials.

Nonblocking recorder, observer and evidence-tool improvements are frozen.
Existing recordings and required validation remain; do not repeat frame/hash
audits or extend static showcase recording infrastructure. The proposed extra
hosted Windows screenshot harness is deferred. Physical Android-to-Windows
Nearby and Cast receiver checks remain explicit external gaps until performed;
additional emulator runs cannot close them. Pending entrant confirmations are
also retained. This changes execution priority, not the meaning of acceptance.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Verified on emulators | Final-source `67d0206` normal install 36103033086 passes API 29/35 debug and API 35 release. The normal debug Test Store APK is prepared with its installation receipt. API 35 first use needed Google SDK Setup ANR recovery; this does not establish the complete repair-free rehearsal |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public AGPL-3.0 repository. Final-source Check 36103033341 passes formatting, analysis, 855 app tests, native player tests, normal debug APK and secret/contracts checks. Main is still the foundation README; implementation is in draft PR #1. Repository merge/closeout remains open |
| 3 | Clear first-launch create/join | Verified on emulators | Final-source five-viewport run 36103033060 and Together 36103033024 attempt 2 pass onboarding, Start, reviewed invitation and Join |
| 4 | Two real clients repeatedly play/pause/seek in sync | Partial | Together 36103033024 attempt 2 passes 26 host and 25 guest stages on two independent phone/tablet emulators. Settled positions match at 8,704, 53,361 and 55,544 ms. Failed-decoder recovery passes 36101860905 on identical product code. Physical hardware remains unverified; sampled position agreement is not frame identity |
| 5 | Real-session chat/reactions/presence | Verified on two emulators | Final-source Together verifies native chat, reaction, presence and peer links. Test Store journey 36103033131 also verifies a premium reaction received by a headless TLS peer |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | Failed-decoder profile 36101860905 passes on identical product code. Latest normal/profile network runs remain failed before recovery assertions; causes and limits below. Final-source lifecycle 36103033022 attempt 2 restores 69 seconds in a new process, paused until explicit Play; Local/Together audio-focus reruns pass. Physical checks remain open |
| 7 | Local Mode and Continue Watching | Partial | Final-source lifecycle preserves 69 seconds across process restart without autoplay or setup repair; SAF relaunch 36103033079 and two-device history also pass. Physical playback acceptance remains open |
| 8 | Secure phone-to-desktop discovery/pair/control | Partial | Final-source Nearby 36103033210 passes pinned TLS, approval, control, revocation and protected persistence on an Android emulator. Normal Windows companion 3ebba3a is packaged by 36103713800. Physical Android-to-Windows discovery/pair/control/revoke/restart remains open |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | Final-source production Test Store 36103033131 passes 12 stages: native cancellation/failure/success, one free and two Plus hosts, appearance/reaction and same-customer Restore after cache invalidation. Relaunch/expiry 36103033020 passes. Physical and Play-production evidence are separate |
| 10 | Correct daily quota and session continuity | Verified in native flows and tests | Latest Together and purchase journeys verify one free host, free joining, unchanged quota after link/media recovery/history and two distinct Plus hosts. Midnight has unit coverage; native journeys do not cross midnight |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | Final-source five-viewport run passes. Normal-release fullscreen 36103033180 passes phone attempt 3 and tablet attempt 2 with original PNG review. Fullscreen idle/transition motion and complete film motion review remain open; physical screens remain unverified |
| 12 | Reliable Cast or exact blocker and fallback | Partial | Android sender and same-room handoff are implemented. No physical receiver is available to this task; receiver availability is awaiting the entrant. Phone playback is the fallback |
| 13 | No placeholders, dead ends or silent failures | Partial | Latest native onboarding, Together recovery/history and purchase journeys pass. Selected final-film frames are inspected; full-motion review and physical acceptance remain open |
| 14 | Clean-install full demo rehearsal | Partial | Final-source Together, purchase, lifecycle and fullscreen journeys pass separately. Their builds and test entry points differ; they do not replace one complete clean normal-APK rehearsal without repair. Install receipt includes SDK Setup recovery |
| 15 | Shipaton submission confidence | Partial | 94-second film, APK, Windows ZIP, icon and screenshot are prepared. Registration succeeded; Devpost draft, artwork, authorized academic email and technical fields are saved (3/5 sections). Public video, academic-email recognition, final rehearsal, physical gates and repository closeout remain open |

## Current verification

### Final-source closeout, September 25

The installable candidate is `67d0206`; its `lib`, `android` and `assets` are
unchanged from frozen product `5f5dd7f`. Later `d8b55b2`/`7bcd6f4` commits prepare
the film and documentation on `feat/submission-showcase`. They do not rebuild
or alter the app. Draft mobile PR #1 remains at `67d0206`.

- [Check 36103033341](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36103033341)
  passes the required format/analyze/test/debug-build and contract/secret checks;
  855 app tests and the native player test suite pass.
- [Together 36103033024, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36103033024/attempts/2)
  passes 26 host and 25 guest stages on independent API 35 phone/tablet emulators.
  Pause/seek checkpoints agree at 8,704, 53,361 and 55,544 ms. Recovery/history
  preserve the original room and hosting ledger. Both native ANR guards pass;
  SDK Setup preparation needs no repair. Two original PNGs are reviewed.
  Attempt 1 completed app assertions but failed when the tablet ADB/driver
  disappeared during evidence collection; it remains a failed attempt.
- [Lifecycle 36103033022, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36103033022/attempts/2)
  uses the normal release APK, preserves 69 seconds in a new process and resumes
  only after explicit Play. No setup repair or observation timeout occurs.
  Attempt 1 exceeded the unchanged four-second HOME advance bound by one second.
- [Purchase 36103033131](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36103033131)
  passes all 12 native Test Store stages, including two distinct Plus hosts and
  same-customer Restore. This is one Android client plus a headless TLS peer.
- [Normal install 36103033086](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36103033086)
  passes API 29/35 debug and API 35 release. API 29 passes an unchanged rerun
  after an incoming-share launch failure. The included normal API 35 debug APK
  enables real Test Store billing; release comparison disables purchases.
  Its first-use receipt includes Google SDK Setup ANR recovery, so it alone
  cannot close the repair-free complete-demo requirement.
- [Fullscreen 36103033180](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36103033180)
  passes phone attempt 3 and tablet attempt 2. Phone rotates into landscape,
  hides both system bars and returns to its original orientation. Tablet starts
  landscape and preserves that orientation. First Back returns to the player;
  second Back returns Home, with the same app process and advancing native
  playback. One original PNG per device is reviewed. Earlier phone attempts
  fail on an observer deadline and recording decode respectively; the final
  unchanged attempt passes. Idle-control/transition motion review is still open.

Final-source playback (36103033062), Nearby (36103033210), SAF relaunch
(36103033079), Together focus (36103033155), Local focus (36103033335),
five viewports (36103033060), RevenueCat relaunch/expiry (36103033020) and runtime
matrix (36103033076) also pass hosted CI. These retain their emulator scope.

Network repeatability remains a disclosed limitation. Normal debug run
`36103033104` stops at `root_missing` before radio loss. Profile run
`36104667364` attempt 1 stops at SDK Home admission; attempt 2 reaches native
playback readiness and sends both radio-disable commands but exhausts the
ten-second settings-readback window before the offline checkpoint. Cleanup
restores radios. Neither attempt evaluates recovery or disproves the prior
accepted `36101860905` run on identical product code. These failures remain
failed; no observer budget or acceptance threshold is weakened, and further
nonblocking observer/recording changes are frozen.

The entrant subsequently requested a Remotion redesign of the final film with
stronger motion and music. That specific creative work is authorized; the
recorder/observer freeze remains. Remotion 4.0.529 is installed in the local user
global executable path, and the existing Codex Remotion skills are in use.
The new composition lives in `showcase/remotion`; heavy rendering stays on hosted
Ubuntu. [Remotion render 36112159786](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36112159786)
passes at `efec08e`, with original music, 1080p H.264 and AAC. Critical scenes and
a short moving Studio preview are inspected. Final editorial acceptance remains
open. The first normal-APK rehearsal `36111219476` prepared both emulators but
stopped before app installation because its driver could not find `adb` in PATH.
`b46d79d` supplies the platform-tools path; rerun
[36112282849](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36112282849)
is in progress. No complete rehearsal pass is claimed.

[Film export 36106912082](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36106912082)
produces the final 94.000-second, 1920 × 1080 silent H.264 candidate. All 2,820
frames decode in hosted CI; representative output frames and the final free-host
card are inspected. Sources, separate runtime boundaries and the complete story
are in [DEMO_SCRIPT.md](DEMO_SCRIPT.md). The entrant authorized a private YouTube
upload, which is saved and verified as private. A bounded 360p browser replay
reached the end with sampled visual checks. Full editorial review and public
video availability remain open; the requested Remotion edition is now in work.
No local emulator or encoding process was started.

The local delivery folder contains the normal Test Store APK, the film,
unsigned Windows companion ZIP, source/build receipts, artwork and rehearsal
instructions. Desktop packaging
[36103713800](https://github.com/PeterShanxin/MeowWatch/actions/runs/36103713800)
and Windows CI `36103713926` pass at `3ebba3a`. This is a build receipt, not
physical Nearby or current Windows UI acceptance.

Shipaton registration and explicit rules/terms acceptance are complete.
The [Devpost project](https://devpost.com/software/meowwatch-mobile) is saved as
**Draft**, with project copy, technology tags, repository links, cover, original
icon/screenshot, Android platform, RevenueCat project ID, authorized academic
email and judge notes. The form shows 3/5 sections complete. The supplied academic
domain is covered by JetBrains/swot, including its documented subdomain rule;
the entrant confirms GitHub sign-in uses that school email. This is domain and
entrant evidence, not a separate Devpost eligibility decision. The final public
video URL and project-specific declarations remain open. No final submission is made.

### Frozen product candidate

The product source is frozen at `5f5dd7f`; `f834327` adds the corrected network
receipt verifier without changing the app. Hosted network run
[36101860905](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36101860905)
passes the full failed-decoder journey in profile mode: real radio/socket loss,
the original guest decoder's native source error, one paused replacement at the
retained 85-second position, room rejoin, and explicit Play/Pause/Seek recovery.
Host decoder 1 remains; guest decoder 2 becomes 3. The room and quota ledger
remain unchanged. Initial convergence takes 4.222 seconds and explicit replay
23.364 seconds; no SDK Setup repair is used. The original result, byte-availability
proof and final native recovery screen are reviewed. This is one API 35 emulator
with two decoders, not physical or two-device outage evidence.

Hosted Together run
[36101169078](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36101169078)
at `5f5dd7f` passes all 26 host and 25 guest stages on two independent phone/tablet
emulators. Native pause/seek checkpoints agree at 13,887, 53,361 and 55,660 ms;
chat, reactions, readable media errors, recovery, history and a new hosted room
also pass. Both final native ANR guards pass without SDK Setup repair. Three
original phone/tablet screens are reviewed; full-film motion remains open.

Normal debug network run `36101166380` stops at the independent observer's
`root_missing` before radio loss; it does not contradict or establish outage
recovery. That observation-tool investigation is deferred under the closeout
freeze. The original failed run remains failed. The final builds and film are
now prepared as described above.

All Android runtimes below are API 35 x86_64 emulators unless explicitly noted.
Original receipts, selected PNGs and recording hashes have been reviewed;
recording gaps and unreviewed full motion remain disclosed. The source and
runtime distinctions below are part of acceptance, not interchangeable checks.
The [investigation history](ACCEPTANCE_HISTORY.md#archived-september-25-native-focus-and-recording-investigations-through-37adcf6)
retains the complete prior results, original failures and repair rationale.

### Earlier integrated source and audio-focus acceptance

Check `36100639201` at `5f5dd7f` passes every required job: 855 app tests,
114 native player tests without skips, normal debug APK, formatting, analysis,
Nearby/platform contracts, observer SDK compilation and media/secret checks.
Original app logs and native JUnit XML are reviewed. The native suite uses
Java 21 for SDK 36; normal Android builds retain Java 17.

Together focus `36100060718` at `86c8e10` passes all three interruption cases
in foreground PID 3448 without SDK Setup ANR repair. The early transient
interruption lasts 354 ms and releases 1,860 ms after the pre-Play marker.
Native pause is observed after 456 ms and room pause after 1,495 ms, including
buffering samples. The 7,541 ms monitor records no native or room autoplay.
Held permanent and transient interruptions pause within 1,044 and 815 ms;
after focus release both native and peer remain at 7,248 and 12,658 ms during
9,389 and 9,786 ms monitors. Fresh explicit Play resumes each case. Android
focus identity/history, same-process foreground state and original receipts
are reviewed; no test-side Pause is issued during interruption. Three original
PNG screens show the real video and paused controls without overlays or
clipping. This gate uses one Android decoder and an independent TLS peer in
the same process; it does not establish two devices or physical hardware.
It retains screenshots and event receipts, not a native video recording.

Normal-release Local Mode `36098502293` at `fffc152` passes in PID 3052 without
setup ANR repair or observation timeout. Permanent pause is observed within
1,387 ms; transient pause within 1,248 ms and automatic resume within 5,323 ms,
then advances twelve seconds. The app stays foreground, and both the helper
and independent observer are removed. Two original transient screens are
reviewed. All three recording hashes match their successful cloud decode
receipts (1,374 frames); gaps are 3.781 and 4.786 seconds. Full motion and
physical hardware remain unverified.

The player uses one native focus owner and a player-scoped interruption event
that cancels Together intent even while buffering. Ordinary buffering does not
pause the room. The [repair history](ACCEPTANCE_HISTORY.md#september-25-audio-focus-repair-through-86c8e10)
preserves the original failures, the Local/Together focus-policy distinction
and the strict Android ownership proof used by the runner.

### Network repair history

Accepted normal network `36080635480` at `4c01143` exercises real radio loss,
cached-address socket failure, two paused decoders, unchanged room/media/quota
on rejoin and explicit Play/Pause/Seek. Initial convergence takes 16.154 seconds
and replay 22.328 seconds on this debug AVD. All 372 native-position records
are retained without rejection/drop, four original PNGs are reviewed and four
recordings match their cloud-decoded hashes. Healthy controller IDs stay the
same; this does not establish failed-decoder rebuilding.

Failed-decoder `36086036490` proves the original guest fails at 85 seconds and
is replaced by controller 3, but first ready incorrectly reports zero while
the restore seek is pending. The target now waits for that seek before ready;
its regression is included in the passing 837 app tests. Subsequent native run
`36090309937` reaches real offline decoder failure but stops before reconnect
because its recording check rejects a 104-microsecond clock difference.

The recording mapping now follows Android 15's actual 90 kHz quantization and
sub-100-microsecond duration reuse; only ffprobe's decimal output has a
0.51-microsecond allowance. Four focused metadata contracts pass. Independent
metadata reads reproduce all 158 and 233 original sample timestamps without
local media decoding. Frame counts, coverage, hashes and strict cloud decoding
remain required. The original run stays failed. Fresh failed-decoder gate
`36092743671` at `37adcf6` passes that recording contract on 186 frames, but
fails initial playback convergence before radio loss: both decoders advance,
yet their last measured positions differ by 3,399 ms. All 100 native reads are
retained without rejection/drop. Neither radio recovery nor failed-decoder
rebuilding was exercised. Small backward room-clock projections repeatedly
invalidate correction evidence after buffering. The current source retains
the original sample age until genuine progress passes its high-water mark;
stall, setter changes and large jumps still revoke eligibility. Candidate
observation tolerates temporary projection wobble, while actual calibration
and its queued recheck retain the original 600 ms clock-error limit. A socket
trace regression and stale/stalled/slow-clock counterexamples are added.
Independent source review caught and corrected a test startup-clock issue.
All 846 hosted app tests pass, including the socket trace regression. Normal
network `36095103607` at `8e31b65` reaches initial playback readiness, then
fails its independent complete-XML capture: the app root appears only after
the eight-second deadline. PID 2972 remains focused; its original screenshot
shows playback. Failed-decoder `36095106426` stops earlier when host controller
1's position query takes more than five seconds. Both decoders are buffering;
the same PID 3244 continues processing room heartbeats, and no decoder error or
replacement occurs. The fixture's 977 byte-span records show ongoing delivery,
no cap wait and a maximum offset well below the cap; they do not prove decoder
consumption or a specific cause of the timeout. Neither run reaches radio loss.
Both original recording hashes match successful cloud decode receipts; the
selected original PNGs are reviewed. Neither failed gate is accepted.

The network AVD still rendered at 1080x2400/420 dpi, unlike the smaller physical
framebuffer used by the focus/lifecycle gates. It now uses the same guarded
pre-boot 540x1200/210 dpi preparation, preserving the phone's logical layout.
Two focused preparation tests cover all three task-owned AVD names, unchanged
dp size and refusal of unknown or ambiguous configurations. The fixture, build
mode, two decoders and all timing/convergence/byte-proof gates stay unchanged.
Fresh run `36096381799` still fails the initial-ready accessibility root capture;
`36096384236` now reaches the 30-second convergence limit with both decoders
advancing but far apart. Neither reaches radio loss. Their preparation receipts
confirm the reduced framebuffer and unchanged logical layout. Reducing rendered
pixels does not resolve these failures; observer and playback evidence need
separate diagnosis. Fresh native convergence and recovery remain required.
Profile comparison `36097713336` uses the same `828f7a4` source and unchanged
failed-decoder gates. It is a build-mode comparison, not a replacement for the
failed debug runs. The normal run's original screen and both recording hashes
are reviewed; both cloud decodes pass. Neither recording establishes recovery.
The profile comparison reaches a real offline Source error at 85 seconds and
rebuilds guest controller 2 as controller 3; paused rejoin restores about 38
seconds. It then fails explicit replay convergence. Its closest qualified
position pair differs by 1,273 ms with only 1.736 ms between the start and end of
both reads, so sequential sampling does not explain the failure. A host
calibration rewinds 2.6 seconds, issues a new HTTP range request and buffers for
about 2.3 seconds while the guest advances. The decoder now retains ten seconds
behind playback, using the upstream native back-buffer option, to allow short
rewinds to reuse media samples. This mitigation needs fresh native verification;
the original profile run remains failed.
Profile run `36099125076` at `6dfc120` observes only the two original HTTP body
requests, with no subsequent refetch, but fails initial convergence before any
outage. All 55 eligible advancing pairs remain over one second apart; the best
is 23,717 / 22,677 ms (1,040 ms) at 29.793 seconds. The later guest read biases
this gap smaller, so sampling cannot establish a hidden pass. The 276 native
position records are retained without rejection/drop, and the 288-frame
recording hash matches its successful cloud decode. No setup repair occurs.
Early self-setter, stalled or borderline room observations defer the first
eligible rate correction until roughly thirteen seconds into playback. At
about one second of lead, 0.95 correction then converges too slowly through
further buffering. The bridge now uses its existing bounded 0.90 rate from a
900 ms lead and returns to 0.95 below 700 ms, with all freshness, buffering,
25-second duration and native acceptance limits retained. A decoder-progression
regression covers both 1.6-second and 1.45-second starting gaps and passes in
all 855 hosted app tests. Fresh native recovery proof remains required.
Fresh profile run `36100587579` at `5f5dd7f` completes every in-app assertion:
initial native convergence in 3.814 seconds, real radio/socket loss, original
guest Source error at 85 seconds, one paused rebuild from controller 2 to 3,
paused rejoin, unchanged quota and explicit Play/Pause/Seek. Replay converges in
6.478 seconds. The first replacement-ready state correctly retains 85 seconds.
The overall job fails because the external verifier expects only two decoder
receipts, while the integration journey intentionally retains both validated
recovery receipts and final snapshots for each role. The corrected verifier
requires both pairs and exact identity/transition agreement through teardown;
missing, duplicate, reordered, false or changed receipts still fail. The original
result reproduces the old rejection and passes the corrected pure parser, but
the original workflow remains failed and a fresh full run is required. Four
original PNGs are reviewed, all 300 position records are retained, and all four
recording hashes match successful cloud decode (947 frames; gaps 2.512, 0.673
and 1.913 seconds). No SDK Setup repair occurs. This remains one profile AVD
with two native decoders; full motion and physical hardware are not established.

Normal network `36091067116` stops before radio loss because its independent
accessibility observer cannot obtain an app root within 15 attempts. PID 3155
and the same unobscured MainActivity remain focused; the original screenshot
shows playback. Its first diagnostic lists only a nonactive system window and
an unfinished root probe. No app ANR/fatal exception is found, but the precise
platform cause remains unknown. A screenshot cannot replace complete XML.

### Earlier accepted core, lifecycle and purchase journeys

- Together `36078687173` at `6daa1ea` passes 26 host and 25 guest stages on two
  independent phone/tablet emulators. Two-way controls settle at matching
  14,541, 53,361 and 55,374 ms positions. Chat, reactions, reviewed links, readable
  errors, recovery, history and one-time new-room quota pass. No setup ANR repair
  is needed. Six PNGs are reviewed; the largest recording gap is 1.785 seconds.
- Normal-release lifecycle `36078684061` at `6daa1ea` pauses on HOME, holds and
  returns paused, then restores 58 seconds in a new process. Explicit Play
  advances ten seconds. Fullscreen `36078690609` passes phone and tablet,
  hidden controls/system bars, orientation restoration and two-stage Back.
  Original receipts and selected PNGs are reviewed; neither needs setup repair.
- Normal install `36074182955` at `29eafe2` passes API 29/35 debug and API 35
  normal release, one launch and no setup repair. Seven incoming-media/invite
  cases preserve explicit confirmation and cancellation. Release is
  non-debuggable but debug-signed with purchases disabled.
- SAF `36074182994` at `29eafe2` retains the actual DocumentsUI grant across a
  process restart and restores eight seconds. Nearby `36074183032` passes
  pinned TLS pairing/control/revocation and protected persistence across three
  processes on one emulator; it is not physical Android-to-Windows evidence.
- RevenueCat Test Store `36074182983` at `29eafe2` passes 12 production-UI stages:
  cancellation/failure/success, one free and two Plus rooms, a premium reaction
  and same-customer Restore after cache invalidation. Three PNGs are reviewed.
  Native recording coverage is 96.796%, with a 3.599-second largest gap.
  Relaunch/expiry `36074183058` preserves the same customer across processes,
  observes real expiry and inactive Restore. Neither proves reinstall identity
  recovery, physical billing or Google Play production billing.

The historical 98-second film candidate from `36059267954` passes strict cloud decoding of
2,940 frames and source-pin/EDL checks. SHA-256:
`5ced046aacf9f55a9b8be9344e27fd3a3266056c298e712ef2ce2b971d5c92c4`.
All 42 shot-boundary PNGs are inspected; all 25 periodic samples are inspected
or match previously reviewed frames. Loading/held frames remain. Full-motion
acceptance and final-build rehearsal remain open; later source fixes are not
represented as present in those clips.

The development PC is limited to source edits, small evidence/metadata reads
and the bounded two-fps static showcase recording. Builds, emulators, full
regression suites and video processing run only in GitHub Actions. The normal
app uses unmodified Flutter 3.44.0 / Dart 3.12.0.

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
The new 94-second edit is exported; full motion and the complete clean-install
rehearsal remain open. Historical runs and asset provenance are preserved in
[Acceptance history](ACCEPTANCE_HISTORY.md).

## Human/external dependencies

- The entrant confirmed active student status, local age of majority, access to an academic email, registration eligibility and explicit rules/terms acceptance. Registration is complete. Academic-email recognition and project-specific ownership/new-work declarations remain separate checks.
- RevenueCat login/Test Store catalog setup and user acceptance of the Android SDK license are complete. RevenueCat email confirmation remains visible.
- Physical Android, trusted physical LAN and Cast receiver availability remain unconfirmed. Emulators and virtual network adapters are not substituted for this evidence.
- Desktop required native/manual review gates remain applicable before merge or release.

## Live development recording

At September 25 05:59 UTC the current bounded two-fps recorder has 270,133,350
bytes persisted in 1,918 chunks, with a newly saved chunk at 05:59:38 UTC. The
latest scoped resource check finds 8.9 GiB available RAM and no local Dart,
Java, FFmpeg or Android emulator.
The selected image is a single
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

The same manifest also retains a 19.652-second heartbeat gap on September 25,
02:49:49.877–02:50:09.529 UTC. The latest resource check and continued saving
do not erase either gap or establish a cause for the earlier machine freezes.

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
