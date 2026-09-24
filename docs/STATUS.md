# Delivery status

Last updated: 2026-09-24 (Asia/Shanghai). **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Partial | Fresh 54b4203 API 35 debug, API 29 debug and API 35 release normal installs pass independent audit, including seven intake reviews and two confirmed playback cases per variant. The late SDK Setup ANR recovery branch is not exercised in this run. Physical acceptance remains separate |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public AGPL-3.0 repository. The 3f16a25 snapshot passes Gitleaks 8.30.1 with zero findings in 513 tracked files and 100 all-ref commits; no suspicious tracked paths. Later revisions need a final scan. Final artifacts and repository closeout remain open |
| 3 | Clear first-launch create/join | Partial | af45d24 passes all five first-use/layout drivers and teardown, including native keyboard visibility after invalid join. The guide's primary instructions and actions remain accessible. 5137e58 production Together passes actual Start, invitation review and Join on independent emulators |
| 4 | Two real clients repeatedly play/pause/seek in sync | Partial | 6c44e415 runtime matrix passes on two API 35 emulators after fixing the stale pause snapshot. 5137e58 production Together also passes all named two-way playback checkpoints. Equal position checkpoints do not establish identical decoded frames or physical-device behavior |
| 5 | Real-session chat/reactions/presence | Partial | 5137e58 production Together passes chat, reactions, presence and confirmed peer-link playback on independent phone/tablet emulators. 2fc38317 purchase also proves the premium reaction received by a TLS peer. Final submission film remains open |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | 8720304 normal release lifecycle passes independent review: real HOME, paused foreground, explicit Play and new-process history restoration. 115454e audio-focus interruption also passes. Actual radio-outage acceptance remains open; failed runs are preserved in acceptance history |
| 7 | Local Mode and Continue Watching | Partial | 8720304 normal lifecycle/history resume and af45d24 five-layout journeys pass independent review. Earlier native playback and SAF relaunch also pass. Each layout retains 20 app steps and 16 screenshots. Physical-device acceptance remains separate |
| 8 | Secure phone-to-desktop discovery/pair/control | Partial | 773d41e Android Nearby passes real pinned TLS pairing/control/revocation and protected persistence across three process runs. Desktop f5a9103 clean Release builds and its actual Windows UI was inspected; dba4b57 updates its dependency pin and passes hosted Windows CI and 1,494 tests. Physical Android-to-Windows discovery/pair/control/revoke/restart proof remains open |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | 2fc38317 production purchase passes 12 stages, one free and two paid hosts, native cancel/failure/success and same-customer restore. The 6c44 runtime billing/hosting jobs also pass. Diagnostic run 35240675074 at 9e032ba passes same-customer process relaunch, accelerated renewals, final expiry and inactive Restore; the earlier 2fc contradictory result did not recur and its cause remains unproven. Physical and Play-production evidence remain separate |
| 10 | Correct daily quota and session continuity | Partial | 6c44e415 runtime hosting passes 14 checks, one free plus two distinct Plus sessions, reconnect and same-process service/disk reopen without recharging. 5137e58 production Together passes endpoint/ledger preservation and repeated-room/free-joining checks. Actual radio-outage continuity remains open |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | Official unpatched Flutter 3.44 at af45d24 passes all five layouts and teardown. All 80 screenshots were inspected and five original videos fully decode; actual native frames confirm keyboard visibility. These are size/density overrides on one AVD. At 56ba16b, phone fullscreen/Back passes native and sampled original-frame review. The fresh tablet capture contains corrupt frames; its complete current Back gate and physical checks remain open. SDK candidate is unadopted |
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
Gitleaks 8.30.1 at `3f16a25` finds no secrets in 513 tracked files or 100 reachable
commits, with no suspicious tracked paths.

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
  a new native run must establish the fix.
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
  transition-frame review pass. Tablet original-recording decode fails as
  above; only that failed job is rerunning with the same strict criteria.
- `35988087246` at `56ba16b`: motion preparation fails on the slider-thumb
  assumption. The repaired `36001965003` probe at `e5e219b` is running remotely.
- `35988489663` at `34b8ea6`: Together history recovery with a 160-record diagnostic
  cap for real native commands, room commands and the Play UI state. Observations
  contain no media URL, room code or participant name; the original 20-second
  playback requirement is unchanged. Static analysis and both actual client
  journeys pass. The host trace proves native seek/Play and advancement about
  5.1 seconds after native Play starts; both clients later pause at 65.381 seconds. Session
  endpoints and quota ledgers remain unchanged. The earlier timeout's cause is
  still unproven. Recorded segment gaps of 3.64 phone seconds and 1.49 tablet
  seconds remain disclosed. This is diagnostic footage, not a final cut.

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
