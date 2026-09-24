# Delivery status

Last updated: 2026-09-24 (Asia/Shanghai). **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Partial | Fresh b523ed5 API 35/29 debug and API 35 release normal installs pass independent audit, including seven intake reviews and two confirmed playback cases per variant. Release succeeds on attempt two after an external Pixel Launcher ANR in attempt one; no app change or dialog repair. The SDK Setup ANR recovery branch is not exercised. Physical acceptance remains separate |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public AGPL-3.0 repository. The 5569701 snapshot passes hosted Gitleaks 8.30.1 with zero findings in 528 tracked files and 130 fetched commits; no suspicious tracked paths. Later revisions need a final scan. Final artifacts and repository closeout remain open |
| 3 | Clear first-launch create/join | Partial | af45d24 passes all five first-use/layout drivers and teardown, including native keyboard visibility after invalid join. The guide's primary instructions and actions remain accessible. 5137e58 production Together passes actual Start, invitation review and Join on independent emulators |
| 4 | Two real clients repeatedly play/pause/seek in sync | Partial | 6c44e415 runtime matrix passes on two API 35 emulators after fixing the stale pause snapshot. c53fc6a production Together profile passes both-way play/pause and host seek on independent phone/tablet AVDs; settled checkpoints have equal native positions. Equal position checkpoints do not establish identical decoded frames or physical-device behavior |
| 5 | Real-session chat/reactions/presence | Partial | c53fc6a production Together profile passes chat, reactions, presence and confirmed peer-link playback on independent phone/tablet emulators. 2fc38317 purchase also proves the premium reaction received by a TLS peer. Final submission film remains open |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | 8720304 normal release lifecycle passes independent review: real HOME, paused foreground, explicit Play and new-process history restoration. 115454e audio-focus interruption also passes. a6a2176 profile passes actual AVD radio loss, visible pause, same-room reconnect without autoplay and explicit resumed controls. New startup recovery changes still need native proof; failed runs are preserved |
| 7 | Local Mode and Continue Watching | Partial | 8720304 normal lifecycle/history resume and af45d24 five-layout journeys pass independent review. Earlier native playback and SAF relaunch also pass. Each layout retains 20 app steps and 16 screenshots. Physical-device acceptance remains separate |
| 8 | Secure phone-to-desktop discovery/pair/control | Partial | 773d41e Android Nearby passes real pinned TLS pairing/control/revocation and protected persistence across three process runs. Desktop f5a9103 clean Release builds and its actual Windows UI was inspected; dba4b57 updates its dependency pin and passes hosted Windows CI and 1,494 tests. Physical Android-to-Windows discovery/pair/control/revoke/restart proof remains open |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | Fresh 8699d3e production Test Store journey passes 12 stages, one free and two paid hosts, native cancel/failure/success and same-active-customer restore; independent evidence review confirms the stated emulator/Test Store boundary. The 6c44 runtime billing/hosting jobs also pass. Diagnostic run 35240675074 at 9e032ba passes same-customer process relaunch, accelerated renewals, final expiry and inactive Restore; the earlier 2fc contradictory result did not recur and its cause remains unproven. Physical and Play-production evidence remain separate |
| 10 | Correct daily quota and session continuity | Partial | 6c44e415 runtime hosting passes 14 checks, one free plus two distinct Plus sessions, reconnect and same-process service/disk reopen without recharging. c53fc6a production Together profile passes endpoint/ledger preservation and repeated-room/free-joining checks. a6a2176 profile also proves unchanged room/media/controllers/free-host ledger through actual radio loss and recovery |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | Official unpatched Flutter 3.44 at af45d24 passes all five layouts and teardown. All 80 screenshots were inspected and five original videos fully decode; actual native frames confirm keyboard visibility. These are size/density overrides on one AVD. At 6aef042, both phone and tablet normal-release fullscreen/Back pass native and sampled original-frame review, including hidden controls, restored bars/orientation and matching paused history. Physical checks remain open. SDK candidate is unadopted |
| 12 | Reliable Cast or exact blocker and fallback | Partial | Android sender and same-room handoff are implemented. Actual receiver acceptance awaits hardware; phone playback fallback is available |
| 13 | No placeholders, dead ends or silent failures | Partial | 2fc38317 verifies guide, loading text, modal transitions, clean install and lifecycle. Later targeted matrix, expiry and production Together runs pass; the prior Restore anomaly remains unexplained. 5137e58 native footage proves readable 404 recovery and normal loading text. Final interruption gates and review remain open |
| 14 | Clean-install full demo rehearsal | Partial | The 2fc cohort remains 8 passing and 3 failed workflows. Later targeted 6c runtime matrix, 9e expiry and 5137e58 production Together checks pass. Final complete rehearsal, interruption coverage and the under-two-minute submission cut remain open; paired recording still has visibly sparse motion |
| 15 | Shipaton submission confidence | Partial | Brand kit and original-size submission screenshot are prepared. Final under-two-minute film, full rehearsal, physical gates and remaining eligibility/legal checks remain open |

## Current verification

The application changes at `773d41e` pass **748 app tests with zero skips**,
formatting of 179 Dart files, static analysis and a normal debug APK build on
unmodified Flutter 3.44.0 / Dart 3.12.0. The portable Nearby package separately
passes **87 tests with zero skips**. Real local TLS tests use loopback and the
explicit Windows WSL virtual adapter; these are not physical LAN checks.
Fresh hosted Check `36015216030` at `5569701` passes **752 app tests**, 87
portable Nearby tests and 14 platform tests with zero Dart skips, all analysis
and formatting of 192 app/harness Dart files. The media job passes both its
15 submission compositor tests and 15 paired-compositor tests with FFmpeg
installed, including the two cases skipped in the separate package job.
Hosted Gitleaks 8.30.1 in the same Check finds no secrets in 528 tracked files
or 130 fetched commits, with no suspicious tracked paths. Raw findings are
never uploaded; the retained receipt contains counts only.

The current repairs and their acceptance boundaries are:

- **TLS cancellation and shutdown (`bd931d5`).** Syncplay and Nearby retain
  the underlying connection through handshake, timeout, replacement and leave.
  Certificate trust or pin, validity and ALPN remain strict. Real socket tests
  cover silent peers, late completions, 8 MiB of backpressure, cancellation and
  final receipts. Independent review reproduced a dropped leaving notification
  in three real TLS tests; all pass after drained shutdown. STARTTLS transport
  failures still reconnect, while malformed answers and failed certificates
  remain terminal refusals.
- **Native startup synchronization (`773d41e`).** An accepted remote Play gets
  one catch-up seek after the native position actually advances. This includes
  source loading into a playing room and Local-to-Together adoption. Pause,
  replacement, connection loss and disposal cancel the watch; correction does
  not echo a user seek. The 1.2-second delayed-start reproduction fails before
  the patch, and all 28 bridge tests pass afterwards. Both independent review
  findings are resolved. The previous native run `35968126247` demonstrated
  actual advancement but a 1.025–1.897 second initial gap, before any radio loss;
  a new native run must establish the fix. Later `a13db64` replaces the original
  wall-clock projection with fresh room heartbeats and permits at most two
  corrections in twelve seconds, rechecking real native advancement after seek
  buffering. Independent review found that an initially aligned sample could
  prematurely remove the watch before a later buffer. `5569701` retains that
  bounded watch, resets queued pending state when no correction is needed,
  and adds the regression. Four new cases pass in the 752-test suite, including
  stale wall-clock projection, bounded follow-up and peer-pause cancellation.
  Native network `36014561148` at a13db64 still fails initial convergence:
  direct command records prove both corrective seeks execute, each immediately
  followed by buffering. At 29.639 seconds, native positions differ by 2.377
  seconds. Ordinary room updates name the slower guest; the leading host is
  below the unchanged four-second rewind threshold. Both players advance and
  teardown succeeds; radio loss is never reached. A bounded review recommends
  guarded one-sided rate correction rather than more frequent seek/rebuffer
  cycles. `a056dda` adds fresh non-self heartbeat eligibility and bounded local
  0.90/0.95 correction, with unchanged convergence requirements. Its first
  hosted checks stop at a trace-map lint before native execution; there is no
  rate-convergence result. A bounded structural review identifies failed 1x
  restoration and an old bridge's queued reset overwriting its replacement.
  The fixes retain dirty state, cap/pause retries and invalidate old queued
  requests; new regressions and native verification are pending.
  Production phone/tablet `36015870817` at 5569701 passes all 26 host / 25 guest
  steps. Independent JSON/hash audit confirms settled pause 10,356 ms, host
  seek 53,361 ms and guest pause 54,691 ms match across devices, unchanged
  endpoint/quota through link/error/history recovery, and new-host charging
  without charging the joining original host. All native ANR guards pass.
  The originals are 165.678/165.496 seconds with 1,544/1,412 pictures; tablet
  has a 0.173-second final gap. Guest recovery/history observations retain
  buffering=true, so these checkpoints do not prove completed frame rendering.
  Hosted original-frame review `36019377413` strictly decodes both originals;
  all retained frame hashes match. Eight original PNGs were inspected. The
  largest picture gaps, 4.640/3.567 seconds, both show static launch icons;
  selected player/chat frames are readable and some retain buffering. Mean
  picture rates are 9.32/8.53 fps. Full-motion acceptance remains separate.
  `8bb79bc` passes hosted Check `36019746397`: 767 app, 87 Nearby and 14 platform
  tests with zero Dart skips, all analysis/formatting and secret scans. Profile
  network `36019751369` reaches the initial-ready checkpoint in about 3.3
  seconds, with native positions 2,499/1,724 ms. No rate command was necessary,
  so it does not exercise native slowdown. The run then fails radio disable:
  wifi reads off but mobile data remains enabled. Original radios and all
  owned resources are restored. No result.json is delivered after runner
  termination, so the retained log/phase/position receipts establish only this
  partial result. The runner now retains `svc` stdout/stderr to diagnose a
  zero-exit framework error or unapplied request without guessing its cause.
  The fresh `3a0307f` PR cohort covers the updated product.
- **Fullscreen intent (`6829cc7`).** Buffering-end may report not-playing
  before the native playing event. Preserving the accepted play intent fixes
  unwanted idle-timer resets, while explicit pause, completion and errors still
  win. The event-sequence reproduction fails before the fix and passes after it.
- **Fullscreen native evidence.** Normal release run `35969876422` at `2184c8e`
  supplies original phone landscape screenshots with controls and system bars
  hidden across 12.94 device seconds, and tablet screenshots across 18.64 seconds.
  All four original MP4s fully decode and their frame clocks cover the required
  observations. Both runs stop before Back because the 90-second fixture ends
  naturally before fresh Pause. `85956cb` extends only that workflow's fixture
  to 180 seconds, retaining every assertion. Earlier normal release tablet run
  `35968302290` completed native pause and Back destinations, with hidden controls
  across 19.01 seconds. Its short Home clip does not show the entire transition.
  The first longer-fixture run stopped at the loaded-paused check because the
  evidence parser still expected 90 seconds. The parser now reads the actual
  file duration and retains the one-second tolerance; 170 fullscreen, lifecycle
  and observer contracts pass. Fresh run `35988087451` at `56ba16b` passes phone
  native playback, pause, orientation/system-bar restoration, first Back and
  Home assertions. Hosted extraction `36002774508` preserves original pixels
  and source frame clocks; inspected phone frames show visible-to-hidden
  controls with continuing video, and the final Back clip runs from the paused
  portrait player to Home with Continue Watching at the same position. This is
  sampled visual acceptance, not every-frame or professional-motion approval.
  Tablet native XML shows
  playing at 1:13/3:00 in fullscreen, but its second original recording contains
  corrupt H.264 macroblocks and is correctly rejected. Device/pulled hashes
  match; the cause of the original encoding corruption remains unproven.
  The tablet-only second attempt stops earlier at `03-normal-playing`: the
  observer traverses 29 nodes but its final instrumentation result times out.
  The `finish` progress marker precedes Android's UiAutomation disconnect and
  instrumentation teardown. The later watcher error follows timeout cleanup;
  it is not established as the initiating fault. A reduced-framebuffer follow-up
  `36007046292` at `6aef042` uses 1280x800 pixels at 160 dpi, preserving the
  original 1280x800 dp tablet layout. The owned pre-launch config, original
  native assertions and all observer/playback deadlines are retained; three
  focused preparation contracts and bounded independent source review pass.
  Fresh run `36007046292` now passes both complete native journeys. Phone
  native advancement is 12 seconds normally and 31 seconds fullscreen; tablet
  advancement is 10 and 18 seconds. All six original clips fully decode and
  independently match their capture hashes/frame clocks. Original quiet PNGs
  show no controls or Android bars across 12.86 phone seconds and 7.92 tablet
  seconds, with changed video content. Hosted extraction `36008913950` supplies
  original source frames: both short Back clips start at the paused normal
  player and end on Home with matching Continue Watching (phone 1:40, tablet
  1:16). The native process remains unchanged and the observer is removed.
  This closes the emulator fullscreen/Back gate, including tablet final result
  delivery; it does not establish physical hardware, every-frame visual review
  or continuous coverage after the final Home frame. Older failures stay retained.
- **Recorder coverage (`2184c8e`).** A timed-out live-file read now retries the
  same byte cursor inside the existing eight-second post-roll deadline. Partial
  timed-out output is discarded and late results fail. All 201 related Python
  contracts pass; original-frame coverage and decode thresholds are unchanged.
- **Paired motion remains open.** Profile diagnostic run `35965651942` passes
  26 host and 25 guest app checkpoints, but the tablet original has a 6.546-second
  interval without a complete new picture. All four recordings decode. This is
  not accepted as professional demo motion. A separate controlled local-player
  capture probe compares two active AVDs against an isolated tablet with the
  same profile APK and native encoding settings; it is not Together acceptance.
  Run `35988087246` stopped before recording because native accessibility
  exposed slider-thumb bounds, which the script incorrectly treated as the
  whole track. `e5e219b` uses actual Back/Forward controls inside one 45-second
  budget and pauses after measured playback before offline processing. An
  unconfirmed recorder stop prevents either file from being analyzed. Failed
  native observations are retained; all 179 focused Python contracts pass.
  Repaired probe `36001965003` passes on two API 35 x86_64 AVDs with the same
  profile APK. Its 30-second two-AVD phase contains 258 phone and 238 tablet
  original pictures; the isolated-tablet phase contains 451, using the same
  tablet process. Maximum picture gaps are 0.476, 0.392 and 0.326 seconds.
  All three originals fully decode and match their device hashes. The hosted
  four-vCPU runner is approximately 97.38% busy with both AVDs and 86.07% with
  the tablet alone. This supports CPU contention as a capture constraint,
  without proving a single cause or professional motion. It does not measure
  the user's computer. The follow-up at `874c9c0` changes only native display
  pixels/density to the recording size, preserving exact logical phone/tablet
  geometry; source timing, original-video checks and playback requirements stay
  unchanged. That run also passes: 341 phone and 266 tablet pictures during
  the paired phase, and 584 isolated-tablet pictures. Their maximum PTS gaps
  are 0.304, 0.301 and 0.172 seconds. Hashes, frame counts and frame spacing
  were independently checked from downloaded originals/metadata without local
  video decoding. Hosted busy time is 95.54% paired and 79.60% isolated. Each
  run uses one APK across its own A/B phases; the separately rebuilt APK hashes
  differ between runs. These are useful measured improvements, not a controlled
  proof of one sole cause, Together acceptance or professional-motion approval.
  Full-resolution acceptance remains separate.

## Current native runs

| Run | Source | Required result |
| --- | --- | --- |
| [35972090941](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35972090941) | `773d41e` | Failed before radio loss: guest native position read times out after five seconds; earlier host/guest reads also slow. The first advancing sample differs by 475 ms, but sustained sync and recovery are not established. Original radios remain enabled; diagnosis continues |
| [35972094368](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35972094368) | `773d41e` | Passed and audited: actual pinned TLS pairing, approval, authenticated control, revocation and rejected old credential; real NSD start/advertise/discover/stop; protected identity and revocation persist across three separate process runs in one install. API 35 x86_64 emulator, same-device transport only |
| [35972097694](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35972097694) | `773d41e` | Failed after Continue Watching: connected and native-ready, but Play did not advance from 65.604 seconds within 20 seconds. The 90.09-second fixture had not ended. Later SIGTERM/driver loss is not evidence of an app ANR. Command and native-state diagnosis remains open |
| [35972199031](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35972199031) | `85956cb` | Both devices stopped before fullscreen because the parser rejected the actual 3:00 duration. No fullscreen recording was produced. Duration parsing is repaired; no observer timeout or playback threshold was relaxed |
| [35973047270](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35973047270) | `01e6ad1` | Probe failed before any capture phase: the runner could not resolve adb although both owned AVDs were ready. The script now validates and uses the session's platform-tools directory. No motion result is inferred from this run |

A passing CI label is not visual acceptance. Original images, native state,
recording integrity and actual runtime must agree. Final current-build clean
install, full rehearsal, remaining physical gates and the submission film remain
open. Earlier acceptance and every retained failed experiment are documented in
[Acceptance history](ACCEPTANCE_HISTORY.md), including the September 24 chronology.

Remote follow-ups after reducing local load:
- `35988087451` at `56ba16b`: phone native fullscreen/Back and sampled original
  transition-frame review pass. Tablet attempt one fails original recording
  decode; attempt two fails observer result delivery as described above.
- `35988087246` at `56ba16b`: motion preparation fails on the slider-thumb
  assumption. The repaired `36001965003` probe at `e5e219b` passes and is audited.
  The recording-size comparison `36005070945` at `874c9c0` passes and is audited.
  Production Together `36007244001` at `c53fc6a` now applies that profile with
  compact original recording and official unpatched Flutter, retaining the
  existing production UI and synchronization assertions. Both drivers pass;
  independent artifact review passes 26 host and 25 guest checks. Both-way
  pauses and the host seek settle at equal native positions; shared media,
  404 recovery and history preserve each endpoint and quota ledger. Native
  history Play advances 60.636 to 63.163 seconds. The guest observation still
  reports buffering, so it does not prove that exact frame finished rendering.
  Both recorders and AVD/server cleanup pass. Original segment hashes match;
  phone/tablet contain 1,622/1,554 pictures over 145.007/146.373 seconds. The
  1.377-second phone tail gap and approximate host-command alignment remain
  disclosed. Hosted original-picture review `36010880333` strictly decodes both
  segments. Mean picture rates are 11.18/10.63 fps; maximum PTS gaps are
  3.755/2.669 seconds. Original pictures on either side show static launch
  icons, so those maxima alone do not prove playback stutter. Selected player
  PNGs show designed phone/tablet layouts and readable room chat; one retains
  a real buffering spinner. Final-shot motion review remains open.
- `36004195131` at `8aced90`: profile compilation and actual profile Dart startup
  pass, but bootstrap incorrectly requires successful store configuration.
  The normal profile build deliberately has no store key. No room, decoder,
  outage or recovery stage runs. `fa08f50` tests the actual unavailable-store,
  non-Plus free-host path for profile while retaining real Test Store success
  for debug; it records and validates both modes explicitly. Production billing
  policy is unchanged. The 37 Python contracts pass with one POSIX-only local
  skip; full checks run on hosted Linux. Follow-up `36006343253` proves the
  expected profile billing receipt, same-PID atomic acknowledgement and two
  real STARTTLS joins. It stops before media load because the script selects
  a URL field before it becomes hit-testable; the profile text-entry path also
  needs the already-tested real-IME helper used by production Together.
  `9dd0caa` reuses that helper and requires both the sheet title and usable field
  inside the same original wait. Its existing three input contracts now run in
  network CI. Follow-up `36007787751` completes every real outage/reconnection,
  recovery and teardown checkpoint with 280 native-position reads and no
  rejected or dropped reads. The extended driver then fails before exporting
  `result.json`: a filename list replaced Flutter's reserved screenshot-data
  field. `c07278a` preserves the framework records and gives filenames their own
  key. Follow-up `36010265073` now exports the full report, but initial playback
  fails before radio loss: a guest position jump is followed by about three
  seconds of buffering and a residual 1.7-second gap. Reads take at most 186ms;
  there are no peer-command or teardown errors. Source review identifies that
  the startup watch is removed before its one corrective seek, and ordinary
  drift handling only rewinds above four seconds. The jump is consistent with
  that correction but lacks direct command evidence. `a6a2176` adds the existing
  bounded native-command trace to both real players (at most160 records each),
  including requested seek position, without URLs/room/user values. Follow-up
  `36012430319` passes and its exported evidence is audited. Seven phases
  complete on one API 35 AVD with two real TLS clients/native decoders; only the
  host is rendered. Both radios actually turn off, the literal-address probe
  reports ENETUNREACH, and original radios are restored in finally. Reconnect
  remains paused, explicit Play/Pause/Seek recover, and controllers, room/media
  and quota ledger remain unchanged. All 178 native reads succeed (356 paired
  records; none dropped/rejected; maximum 648 ms). Initial convergence takes
  20.918 seconds at a 939 ms gap; resumed Play takes 5.644 seconds at a 986 ms
  gap. These satisfy the unchanged <1-second gate but do not establish tight
  sync throughout startup. Four original recordings pass hosted full decode,
  independent hash checks and required observation coverage. Original offline
  and reconnected PNGs visibly match the paused states. This precedes the
  a13db64/5569701 production fixes and cannot verify them.
- `35988489663` at `34b8ea6`: Together history recovery with a 160-record diagnostic
  cap for real native commands, room commands and the Play UI state. Observations
  contain no media URL, room code or participant name; the original 20-second
  playback requirement is unchanged. Static analysis and both actual client
  journeys pass. The host trace proves native seek/Play and advancement about
  5.1 seconds after native Play starts; both clients later pause at 65.381 seconds. Session
  endpoints and quota ledgers remain unchanged. The earlier timeout's cause is
  still unproven. Recorded segment gaps of 3.64 phone seconds and 1.49 tablet
  seconds remain disclosed. This is diagnostic footage, not a final cut.

Current clean-install cohort `36011248229` at `b523ed5` passes API 35/29 debug
on attempt one and normal release on attempt two. All APK hashes independently
match install/intake receipts. Each normal lib/main.dart build passes seven
cold/warm intake review/cancel cases and two explicit playback cases advancing
3–5 seconds. Content URI permissions remain transient and read-only; fixtures
and observer are cleaned up. Original first-launch clips pass hosted full
decode; release onboarding is visually readable and unobscured. API 29's
ActivityManager wait timeout is retained alongside actual app focus/onboarding
and later playback. Release attempt one is retained: a **Pixel Launcher** ANR
covers already-rendered onboarding. The exact app-focus gate correctly fails;
retry passes with no app change, weakened assertion or dialog repair. This is
not evidence of a MeowWatch ANR. All builds use debug signing; release billing
is deliberately disabled. These are emulator results, not Play production.

Fresh Test Store journey `36013144021` at `8699d3e` passes 12 stages and bounded
independent evidence review. Native Test Store dialogs record cancel/failure/
success (errors 1/42 then Plus); three distinct rooms show one free host and two
Plus hosts without further free consumption, native playback and a real TLS
peer. Restore, paid themes and premium reaction are verified. The peer runs
headless in the same process; Restore uses the same already-active customer.
One customer hash plus driver assertions does not independently establish
identity continuity across reinstall or devices. The immediate success PNG
still shows loading; later unlocked-room/entitlement evidence establishes the
result. Three native recording segments cover 98.07% of the journey with a
1.751-second maximum gap. This is not uninterrupted visual or physical-device
acceptance, nor a Google Play transaction.

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
