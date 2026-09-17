# Acceptance history

Historical checkpoints retain the scope and failures of their tested source. Current acceptance is in [STATUS.md](STATUS.md).

## Historical native acceptance: `9b7e9ed`

This earlier native acceptance source is `9b7e9ed08d0d83487441678b0aaee342d690138f`.
All 11 workflows have finished: **7 pass and 4 fail**. All native evidence below
uses Android emulators, not physical hardware; local follow-up corrections are
outside this CI head.

[Check 35212468150](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468150)
passes 654 app tests, 76 TLS tests, 14 platform tests, formatting of 178 Dart
files, static analysis and the checked Python/Bash/media contracts. The native
[playback 35212468122](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468122)
and [Nearby 35212468334](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468334)
workflows also pass. Gitleaks 8.30.1 finds zero findings in 452 tracked files and
36 all-ref commits; the recorded before/after HEAD matches this commit.

The fresh [production purchase 35212468110](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468110)
passes all 12 stages: one free host, cancellation/failure/success, same-customer
restore, persisted Glass Aurora, peer-received premium movie-night reaction and
persisted Cinema Noir, plus two distinct paid hosts with native playback.
Artifact review confirms the 12 critical screenshots and finds no unexpected
system modal in the reviewed footage. Its three original recordings are not
continuous: host recorder-coverage gaps are 1.281/1.705 seconds, while segment
UTC starts plus playable durations imply approximately **3.384/2.623 seconds**
between playable timelines. Edits must retain visible cuts; coverage metadata
must not be presented as full playable coverage. This remains one native Android
player and an independent headless TLS peer, not two filmed devices.

[RevenueCat relaunch and expiry 35212468121](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468121)
also passes. The real Test Store purchase at 10:58:48 UTC has expiration
11:03:48 UTC; fresh SDK observations retain the same customer and original
purchase. The second bounded polling segment observes inactive Plus at
11:03:52 UTC, and a cache-invalidated restore remains inactive with the same
historical entitlement. This is actual SDK expiration evidence, not a clock or
entitlement simulation. [SAF relaunch 35212468083](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468083)
passes independently. Its two processes have PIDs 3656 and 5240; the second
retains the content grant, restores position 8,000 ms and resumes actual decoded playback. App data is kept
between process runs; this is not reinstall/lost-data recovery.

[Runtime matrix 35212468247](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468247)
passes all three jobs: independent phone/tablet synchronization, native Test
Store billing and hosting/quota checks.

[Normal installation 35212468289](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468289)
passes its release API 35 job, including new confirmed HTTPS sharing and content
URI playback (12/9 seconds displayed advancement), temporary read-only grant
verification and owned fixture cleanup. Debug API 29/35 fail the new incoming
branch: provider-byte readback and a missing active-window hierarchy respectively.
Local corrections address the provider CLI invocation and held UI capture;
51 runner contracts pass, but the debug branches still need native execution.
[Normal lifecycle 35212468238](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468238)
gets past observer installation and observes native playback from 14 to 34
seconds, then rejects a valid MP4 because its metadata does not match the
validator's assumptions. The separate host-clock observation error is also
corrected locally. Those changes pass 64 contracts; no native HOME/resume/restart
pass is claimed from this failed run.

[Product journey 35212468253](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468253)
passes phone, portrait tablet, landscape tablet and landscape phone. Each has
20 app steps and 14 screenshots covering guide/replay, Local playback, history,
the real Sintel sample and offering/appearance entry. Small phone also records
all 20 steps and 14 screenshots, then fails Flutter semantics teardown at
`object.dart:6670`; its driver and the full five-layout workflow are failed.

[Production Together 35212468221](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468221)
reaches real create/join, two-way native control and rendered social checks.
The guest reaches these checkpoints after the required ML Kit generated-image
QR decode and explicit Join; that execution prefix does not establish camera
hardware or a passing final verified ledger. The extended shared-link flow
encounters its first Flutter semantics assertion at 11:04:36 UTC
(`object.dart:6670`, followed by `5713`); the guest then times out waiting for
shared-link playback. Recovery and repeat-room branches remain unaccepted.
Original recording review exposes an earlier MeowWatch ANR at 11:01:12 UTC
(focus dispatch timeout, app PID 3306). Its system dialog obscures the phone
while the Flutter driver continues injecting widget actions beneath it. Those
steps do not prove an unobstructed user journey. The recorder/compositor itself
passes, preserves both actual display geometries and retains a largest phone
rotation gap of 19.126 seconds. No clean paired preview interval exists in this
run. The local native ANR guard now fails on a fresh app ANR, stops only its
owned host driver process group and retains native diagnostics. Both roles are
checked again after both drivers finish, including when either driver fails.
The application's ANR is never dismissed automatically. All 32 Together runner
contracts pass locally; this guard still awaits native CI execution.

The shared-link branch also exposed a separate double-close navigation race:
the successful load auto-closes its sheet while a late Close callback can pop
the underlying route. The local fix restricts the callback to its own current,
active sheet and makes the journey wait for automatic dismissal. Both race
regressions and all 10 chat widget tests pass. The preceding ANR and first
semantics assertion still need independent resolution and native verification.
The updated application also passes all 656 tests on the unmodified installed
SDK; the normal debug APK builds successfully. These local checks do not replace
the pending native rerun.

The local semantics-on route-teardown reproduction passes four sequences at the
actual phone and small-phone dimensions/DPR, using real MainApp routes and
widget-only billing. It does not reproduce the native assertion or include Android
surface capture and does not establish a framework fix.

A separate upstream overlay regression fails on the unmodified Flutter 3.44.0
SDK and passes with the fixed 14-line patch from the still-unmerged
[Flutter PR #190431](https://github.com/flutter/flutter/pull/190431), pinned at
`65e4783d8a1019029da88ee2435892ef638a9937`. An isolated copy of the app also passes
656 widget/unit tests against that copied framework. The installed SDK is
unchanged. Explicit manual candidate workflows copy the SDK into disposable
runner storage, verify source/output hashes, run the upstream regression and
keep their results separate from baseline acceptance. The 18 preparation
contracts and local read-only real-SDK hash check pass. This is diagnostic work;
neither adoption nor a fix for native `object.dart:6670` is established.

The next two-player CI run uses physical phone 720 × 1600 at 280 dpi and tablet
1280 × 800 at 160 dpi, preserving their previous logical geometry while reducing
software-rendered pixels. The launcher aligns the AVD LCD and skin configuration
and rejects a mismatched physical readback or display override. A measured
240-second cold-boot admission policy runs before installation or recording;
the invite rendezvous starts afterward so its 900-second lifetime is preserved.
All 30 local multi-device tool contracts pass, including 17 readiness contracts
and an actual fake-ADB CLI subprocess sequence. These are harness checks, not
evidence of improved native performance. The five-layout acceptance keeps its
separate full-resolution captures.

## Previous native follow-up: `6edcb03`

The production application is unchanged from `70575be` at this commit; the
follow-up changes acceptance harnesses, recording preparation and documentation.
Subsequent local feature changes are not covered by these results.

- [Check 35208903864](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35208903864)
  passes 648 app tests, 76 TLS tests, 14 platform tests, formatting, analysis and
  all checked runner/media contracts. Gitleaks 8.30.1 reports zero findings in
  444 tracked files and 32 all-ref commits at this exact head.
- [Normal installation 35208903866](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35208903866)
  passes debug API 29/35 and release API 35. The original install/storage and
  recorder-finalization failures are resolved in these emulator jobs.
- [Production Together 35208903827](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35208903827)
  has passing host and guest application drivers and result files: real Start,
  Join, native two-way play/pause/seek, rendered chat and reactions. The host
  records 16 verified steps and the guest 15. Its workflow still fails recording:
  the phone's first screenrecord cannot open its owned output path, reporting
  `Operation not permitted`, and no phone MP4 is retained. This is application
  behavior evidence, not an accepted paired demo film. The tablet's observed
  viewport is portrait 1600 × 2560 despite its landscape-native display; framing
  must follow the actual capture geometry.
- [Runtime matrix 35208903798](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35208903798),
  [playback 35208903822](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35208903822),
  [SAF 35208903805](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35208903805),
  [Nearby 35208903810](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35208903810)
  and [RevenueCat relaunch 35208903904](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35208903904)
  pass. These remain emulator and same-customer/same-device evidence at their
  documented boundaries.
- [Normal lifecycle 35208903865](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35208903865)
  now installs its observer successfully but rejects the instrumentation listing
  during preparation. Android's package manager emits the short component name;
  the runner required its full form. The local correction preserves the exact
  self-target check and passes 57 observer/lifecycle contracts; native execution
  is still required.
- [Production purchase 35208903797](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35208903797)
  fails waiting for native playback and real peer play observation in the first
  paid hosted session. The decoder and peer were present, but the one Play action
  was not accepted. Existing intent ordering does not establish that an initial
  pause overwrote it. A stable native/peer initial-pause precondition and exact
  lifecycle/play diagnostics await native verification; the earlier passing
  purchase run below remains historical.
- [Product journey 35208903814](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35208903814)
  passes small phone, portrait tablet and landscape tablet. All four non-landscape
  phone profiles tap the real Sintel sample, decode 52,209 ms and observe at least
  four seconds of progress. The phone completes its app steps but fails a Flutter
  semantics assertion while disposing the app; this is not an accepted driver
  result. Landscape phone fails because its compact playback tooltip differs
  from the harness lookup. The lookup correction reuses the existing compact
  control finder. The independent teardown assertion remains under investigation.

The full-spec coverage pass additionally identified missing rendered history
timestamps and unproved native branches: actual subscription expiry, invite QR
decoding through confirmed joining, peer video links, failed-media recovery,
room-history resume/new-room replay, accepted Android media sharing, Glass Aurora
and the paid reaction pack. Local work is addressing these explicitly; existing
happy-path checks are not counted as evidence for them. History timestamps now
render using the device's local date/time format and pass five existing Home/
recent-room widget checks. Six QR camera-substitute widget tests pass, including
confirmation, foreign-code rejection, cancellation, denied permission and exact
scanner release. Four disposable actual-widget renders cover phone, small phone
at 200% text, landscape phone and landscape tablet; history timestamps and the
Join scanner entry were inspected without overflow. These are widget evidence,
not native camera or device acceptance. Native ML Kit image decoding is added to
the real two-client invitation flow and still awaits execution.

## Previous native checkpoint: `70575be`

Fresh CI below uses `70575be5c9d1cc89f25ff0b6ee68451380eb9056`. A passing individual job is identified separately when its containing workflow failed. All native runs below use Android emulators, not physical devices.

- [Check 35199455103](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455103) passes **648 app tests**, **76 TLS tests**, **14 platform tests**, formatting, analysis and runner contracts.
- [Product journey 35199455174](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455174) passes phone, small phone, portrait tablet, landscape tablet and landscape phone: **18 verified steps and 13 screenshots per layout**. These include the three-step first-use guide preserving the entered name, Settings replay, actual decoded video, play/pause/seek, Continue Watching, real RevenueCat offering and the premium-appearance upgrade path. The previously failing landscape profile now reports actual **1600 × 720** pixels. Native guide frames were inspected on phone, landscape tablet and landscape phone.
- [Native playback 35199455129](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455129) opens the officially hosted **Sintel** trailer: **52,209 ms**, **854 × 480**, **1,175 ms** observed progress and a **10,000 ms** seek. The decoded opening mountains were inspected. This is native direct-URL playback proof; it does not by itself prove the new media-sheet sample button was tapped.
- [Production purchase 35199455085](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455085) passes **10/10 stages** through MainApp: one free host, quota paywall, native cancellation/error/success, same-customer restore after cache invalidation, persisted Cinema Noir and two distinct paid hosts with peer-observed play. It uses one native Android player and an independent headless TLS peer in one process. Its two raw recording segments have a **1.471-second gap** and are not continuous footage. [RevenueCat process relaunch 35199455183](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455183) also passes; neither run proves recovery after reinstall or lost customer identity.
- [SAF process relaunch 35199455134](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455134) and [Android Nearby 35199455261](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455261) pass. Nearby remains same-device transport evidence; physical Android-to-Windows LAN and Cast receiver behavior require separate acceptance.
- [Independent phone/tablet job 105130438308](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455118/job/105130438308) and the separate native Test Store job pass in [matrix 35199455118](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455118). The matrix workflow fails its hosting/quota job, which remains under diagnosis. [Production Together 35199455070](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455070) has now failed and remains under diagnosis; no full production UI social-journey success is claimed from the separate matrix job.
- [Normal installation 35199455060](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455060) passes release API 35 with billing unavailable. Debug API 35 fails storage preparation; API 29 completes its UI checks but fails recorder finalization, so neither debug job is accepted. [Normal lifecycle 35199455111](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455111) fails preparing the native observer helper. Narrow runner corrections are in progress; these failed runs do not demonstrate HOME/replay/restart behavior. These APKs use Android debug signing, not production Play signing.
- Gitleaks **8.30.1** reports **zero findings** in **442 tracked files** and **28 all-ref commits**, using default rules, ignored inline allow comments and an empty ignore file. The retained report is `.local/verification/secret-audit/20260917T082301Z-70575be5/summary.json`; its before/after HEAD values match this checkpoint. This does not cover subsequent edits or final release contents.
- Raw-film review found a persistent **Pixel Launcher** ANR in all five product-journey profiles, already present before MeowWatch launched. Flutter's surface screenshots omit this system overlay. Passing app steps and inspected app pixels therefore do not establish an unobscured end-to-end recording. A separate Google SDK setup ANR covers the production purchase run's early free-host interval; its later purchase/restore/paid-host clips are unobscured. Retain these original failures and recapture the guide after strict emulator preflight; do not replace obstructed motion with clean stills.
- The prepared icon and cover remain available. The [native submission screenshot](../assets/submission/meowwatch-android-1179x2556.png) now has [verified `70575be` provenance](../assets/submission/screenshot-provenance.json) from purchase run 35199455085. Its Home pixels happen to be identical to the earlier capture; the new source is verified rather than inferred. The current submission kit includes the original 1179 × 2556 PNG and full source hashes. The final film and integrated rehearsal remain open.

## Historical local verification before `9b7e9ed`

Formatting and analysis pass, and the normal debug APK builds successfully.
The app suite passes 644 tests with ten adapter tests skipped because the first
invocation lacked the adapter variable; a separate exact target run on the
enumerated 172.27.224.1/20 adapter passes all eleven tests, including those ten.
This covers 654 distinct app tests, including six new scanner tests. Four
disposable layout renders also pass. The relevant observer, lifecycle, install, billing,
purchase, Together and incoming-media Python suites pass 192 contracts. Recorder
contracts cover 13 scenarios plus argument boundaries; Bash syntax passes.

The phone teardown failure above matches the open Flutter
[semantics geometry report](https://github.com/flutter/flutter/issues/189902#issuecomment-5086415367),
including a report on 3.44.8. This similarity is not a confirmed root cause or a
fixed issue. No assertions or accessibility semantics are disabled. A bounded
route-teardown reproduction is being prepared; a later passing run must not be
described as proof of a framework fix.

New native coverage and recorder/observer corrections await CI. No local widget
or contract result is counted as camera, physical LAN, purchase expiration or
clean paired-film acceptance.

## Historical local preparation for `6edcb03`

The production journey additionally taps the media chooser's sample button after Continue Watching and checks its decoded result. That extended journey expects **20 steps and 14 screenshots per layout**; the `6edcb03` outcomes above supersede the earlier pending state.

The hosting harness now uses accepted play intent rather than a transient native buffering flag before requesting pause. The production Together harness waits for accepted pause intent and a stable native position before publishing its test checkpoint: at least 800 ms, nine samples and less than 350 ms total movement, within the existing 45-second bound. Its cross-device 800 ms comparison is unchanged. Original recordings show both devices eventually paused at visible 0:56 while the host reports 56,467 ms; the earlier guest checkpoint value was not retained, so premature optimistic sampling is a source-supported diagnosis rather than a recovered numeric measurement.

Local analysis passes in **7.0 seconds**, **17 controller tests** pass, and **90 install/native-observer/lifecycle/intake Python checks** pass. The strict system-ANR preflight passes **12 tests** plus **31 existing native-dialog selector tests**; Bash syntax and formatting checks pass. Normal install storage/recording, helper installation, and the new settled-pause/sample-picker checks still require fresh native CI. Historical counts below retain their original scope and commit.

## Historical implementation checkpoints

The following entries retain evidence and failure history from earlier builds.
Their pending-work statements describe those checkpoints; the current table
and `9b7e9ed` results above govern present acceptance.

### Pre-`70575be` local verification

This subsection records checks performed before the fresh CI above; its pending statements are historical.

The current follow-up adds an optional three-step first-use guide and Settings replay without changing the existing name/Continue flow, room state or quota. The media chooser offers the unmodified, officially hosted **Sintel** trailer with Blender Foundation/CC BY 3.0 credits; it uses the normal direct-video path and requires an explicit tap. Source labels describe Android files and direct media links, not unsupported webpage platforms. The avatar foreground contrast is also corrected locally.

- Local verification passes **648 unique app tests**: the full suite first passed 638 with ten Nearby tests skipped because the runner used the wrong environment-variable name; all ten were then exercised successfully with the corrected network configuration (11 tests in that focused rerun, including one duplicate). This is same-host TLS over the Windows virtual adapter, not physical Android-to-Windows LAN proof. Focused coverage includes **21 guide/settings/onboarding/media UI tests**, **36 bridge/Cast tests**, and **67 Python observer/lifecycle/compositor tests**; these are subsets or separate tool tests, not additional native acceptance counts.
- Formatting covers **171 Dart files** and the final analysis passes in **9.0 seconds**. The final normal debug APK builds locally in **23.9 seconds**. These local checks do not replace a fresh install or emulator/device run of the changed product.
- Actual-widget review passes **four rendered journeys with 52 screenshots** across 412 × 892 phones, 360 × 640 phones at 200% text, 1280 × 800 tablets and 800 × 360 landscape phones. Capture uses production `MainApp`, real bundled fonts and normal guide/settings/media interactions, including all three guide pages and sample credits. Review found the default drag handle floating above transparent custom sheets; six custom sheets now disable that handle while retaining their close controls. After the correction, **53 sheet tests plus all four preview journeys pass in 71 seconds**; inspected phone, tablet and landscape images confirm the stray handle is gone. Screenshots remain local under `.local/visual-review/guide-followup/`. This establishes widget rendering, not Android-device behavior; new native guide/sample gates still await fresh CI.
- Native failures from `feaeb77` are diagnosed but remain unaccepted pending fresh CI:
  - Lifecycle: the moving 100 ms timeline prevents UIAutomator's idle wait from completing. A task-owned `UiAutomation` observer reads without waiting for idle and validates the process and a fresh nonce; it adds no app testing hook.
  - Production Together: a global chat-text assertion matched both the legitimate phone preview and the message bubble. The assertion now targets the visible chat panel.
  - Two-AVD playback: a reproduced late native play echo, arriving after the previous three-second settling window, could undo a peer pause. The production capability/reassertion correction addresses this state race. Acceptance still requires no more than 350 ms of native movement over a continuous 800 ms window with nine samples, inside a bounded 45-second wait.
  - Simultaneous full-resolution recording under SwiftShader caused long EGL stalls. Only recording resolution/bitrate is reduced (phone maximum 1600, tablet maximum 1280; 3 Mbps); this mitigation is separate from the production pause correction and is not claimed to prove it.
  - Landscape: Android reverted rotation during launch. The runner now requests explicit 1600 × 720 bounds at rotation zero and still asserts the actual rendered orientation.

The accepted and failed historical results below retain their original commit and counts. Local corrections, passing unit tests and recording changes do not establish native acceptance.

### Prior CI checkpoint: `feaeb77`

The verified CI commit is `feaeb77a02c6f3274e78caf861ddf62a2253e219`.
Local follow-up fixes listed below are not covered by its results.

- [Check 35194003145](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35194003145) passes **633 app tests**, **76 TLS tests**, **14 platform tests**, formatting, analysis and runner contracts. The submission compositor's 13 contracts pass, including real FFmpeg rendering of explicitly synthetic fixtures. These checks do not establish native product acceptance.
- [Normal installation 35194003268](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35194003268) passes all three jobs: debug API 29, debug API 35 and release API 35, all x86_64 emulators. Debug uses the real RevenueCat Test Store; release has billing unavailable. Both are Android-debug-key artifacts, not a production-signed Play release. API 35's ActivityManager draw-wait timeout is retained in diagnostics; native onboarding and stable-process checks establish the accepted launch.
- [Production purchase 35194003110](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35194003110) passes all **10/10 stages** through MainApp, including native cancellation (code 1), failure (code 42), success, cache-invalidated same-customer restore and persisted Cinema Noir. The session ledger records one free and two distinct paid sessions with native progress and peer-observed play. This is one native Android player plus a headless TLS peer in one process. The original recordings contain a measured 1.737-second segment gap; the successful purchase-to-unlock sequence is within one segment. Neither this run nor the passing [RevenueCat process relaunch 35194003179](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35194003179) proves recovery after reinstall or lost customer identity.
- [Product journey 35194003118](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35194003118) passes phone, small phone, portrait tablet and landscape tablet. Each has 16 verified steps and nine screenshots. The phone-landscape run completes those app steps but renders 720 × 1600 portrait; the strict driver orientation check correctly fails it. Android logs show rotation reversion during launch. The runner now requests explicit 1600 × 720 bounds at rotation 0; its shell syntax passes, but fresh native execution is required.
- [Playback 35194003106](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35194003106), [SAF process relaunch 35194003104](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35194003104) and [Android Nearby 35194003089](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35194003089) pass. These remain emulator and same-device transport evidence; Android-to-Windows LAN and physical media/receiver behavior are separate gates.
- [Normal lifecycle 35194003102](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35194003102) fails in `03-playing`: three 10-second UIAutomator hierarchy reads time out after the loaded-paused observation. It does not reach accepted HOME/resume/process-restart evidence. The native observer change awaits fresh proof. [Production Together 35194003084](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35194003084) and the independent two-AVD job in [matrix 35194003095](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35194003095) also fail and remain under diagnosis. The matrix's separate native billing and hosting/quota jobs pass; the workflow as a whole does not.
- The original [1179 × 2556 native home screenshot](../assets/submission/meowwatch-android-1179x2556.png) is copied without resizing, cropping or framing from the passing purchase run. Its SHA-256 is `ee8f0731e5b0ec7ffbaa1bba9d66d5efd9b8a23553f6b692ca7a23264dc3e50a`; [provenance](../assets/submission/screenshot-provenance.json) records source APK `0251abe9f9df09fdc60c8c4ea80c2c6d4826bb28116a62d89fa86f961bf25513`, full commit, native runtime and source recording hashes. The icon and 1200 × 800 cover are prepared. Avatar contrast has a local correction pending native review; the screenshot remains labeled with the build it actually captured. The final 110-second film and integrated rehearsal are still open.
- Gitleaks **8.30.1** reports zero findings in **432 tracked files** and **23 commits across all refs** with default rules, inline allow comments ignored and an empty ignore file. The retained local report is `.local/verification/secret-audit/20260917T072032Z-feaeb77a/summary.json`; its before/after HEAD values both match this checkpoint. This is a scoped scan result, not a guarantee about later edits or final release contents.

### Earlier checkpoints

- `flutter test --no-pub --concurrency=2 --reporter expanded --dart-define=RENDER_UI=true`: **627 passed** with the actual local `172.27.224.1/20` adapter selected for TLS client tests; no LAN skips. Tests include five rendered layouts, 200% text, long player times, landscape keyboards, screen selection, paywall accessibility, incoming media, appearances, reaction packs, repeat movie nights, per-player audio policy and honest restore-error feedback. The virtual adapter exercises same-host transport, not physical LAN discovery.
- `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` passes with 167 files unchanged; `flutter analyze --no-pub` reports no issues (156.1 seconds).
- `flutter build apk --debug --target=lib/main.dart`: passed with the cat-and-play brand, production UI, native share bridge, Cast and bundled fonts on the local Windows ARM host (124.5 seconds). That retained normal debug Test Store APK SHA-256 is `d1bfba0c2ee54dddc4bbd904056e4d1be935db7cec5e95455104fb7a9e319e2f`. Native icon/splash execution was pending at this earlier checkpoint; newer install evidence is above.
- `flutter build apk --release --target=lib/main.dart --dart-define=REVENUECAT_API_KEY=` also passes (70.1 MB, debug-key signed). Its SHA-256 is `d0d0046dcbe6d63747056690bfa0fb22fe67a797bd35cd36347208684247372b`; this artifact intentionally has purchases unavailable and is not the Test Store judging build.
- `flutter build apk --debug --no-pub -t integration_test/playback_smoke_test.dart`: passes on the same host.
- `dart run test/support/syncplay_live_smoke.dart`: two public STARTTLS clients; bidirectional control, social signals, presence and reconnection. See [SYNC_CORE.md](SYNC_CORE.md).
- Production onboarding, home, join, player, chat, invitation, media, settings, Nearby and real-offering paywall screens are implemented. Nearby still needs cross-device acceptance and Cast work continues; this is not a submission-ready build.
- [Native Android playback run 35054195277](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35054195277) passed on an API 35 Pixel 6 x86_64 AVD. Actual video texture screenshots and a 44.17-second native recording were inspected: 1280×720 media decoded, play advanced 773 ms, and seek reached 2018 ms. This is emulator evidence, not physical-device proof.
- [Two-AVD run 35058753994, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35058753994) booted independent phone/tablet clients and played native video. It failed when a pause stability assertion sampled before the subsequent authoritative seek had converged. The corrected test waits for both pause and the actual native position, then retains the original 350ms drift bound. It has not yet passed; recordings are development evidence.
- [Native production journey run 35061089564](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35061089564) passes onboarding, local playback, seek, durable Continue Watching and the real offering on all five viewports: phone, small phone, portrait tablet, landscape tablet and landscape phone. All five results have exit 0, seven native screenshots and a raw screen recording. Critical images were inspected; the prior safe-area overflow and paused buffering indicator are fixed, tablet home uses two columns, and the offering shows its monthly price period. This remains AVD evidence.
- [Native RevenueCat job 104671008222](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35057627571/job/104671008222) passed: real `default` offering, `$rc_monthly`, localized `$2.99`, initial entitlement false, cancel code 1, failure code 42, successful purchase activates `meowwatch_plus`, server refresh and restore retain it. Native dialog screenshots and three recordings were retained. This uses the official Test Store on an emulator; it does not prove a Play Store charge, physical-device billing, or the integrated hosting funnel.
- Nearby packages: **76 pure Dart primitive/authority/TLS client/server tests** and **14 protected-store/discovery contract tests** pass. Self-revocation immediately retires control and acknowledges success only after durable storage; failure/timeout never returns success. These counts are not all hardware tests.
- The isolated Windows Release native probe passed three separate processes: protected identity/credential write, restart/read/revoke, and restart/revocation persistence. Actual network-profile enumeration reports a Public network and correctly rejects eligibility. No network-profile or firewall setting was changed. The actual Release MediaKit probe also passes all ten dispatch checks after fixing a stale decode-probe marker that incorrectly sought back to EOF during replay: playback advances 500ms, paused drift is 0ms, seek reaches 1614ms exactly, and replay advances from zero to 266ms. This tests native player dispatch, not paired cross-device transport.
- [Android Nearby run 35063448908](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35063448908) passes protected identity/credentials, namespace isolation, two process restarts and persistent revocation. It also verifies native private-interface enumeration, discovers its real NSD advertisement and completes pinned TLS pairing, owner approval, fresh-client authentication, control and revocation. This same-device transport check does not substitute for Android-to-Windows LAN evidence.
- [Two-client native run 35063448706](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35063448706) has passing host and guest Flutter drivers and results, including two-way playback, pause convergence, seek, reaction and unchanged guest quota. The recording gate failed: tablet went offline while transferring its final segment; phone transferred its segment but remote cleanup failed. The recorder now retries bounded exact-device transfers and distinguishes cleanup warnings from missing footage. This older failure is superseded by the complete raw-segment collection in run 35074802807.
- [Product journey run 35063448648](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35063448648) passes all five native viewports again. Native RevenueCat cancel/failure/purchase/refresh/restore also passes in product run 35063448706. Its integrated hosting preflight failed at that checkpoint; real purchase success alone does not prove unlimited hosting.
- Product matrix run 35061089615 exposed three separate issues: a Pixel Launcher ANR obscured the billing dialog, two decoders in the same-process hosting harness competed for audio focus, and the dual-AVD host never attached to its VM service. The first two have narrow test-environment corrections with unchanged product assertions; host launch diagnosis continues. No failing run is counted as accepted co-watch evidence.
- Linux TLS revocation receipt delivery now closes the output gracefully while draining remaining input before a bounded hard close, avoiding a reset that discarded the success receipt. The complete 76-test protocol suite passes on Linux as well as Windows.
- [Desktop companion draft PR 279](https://github.com/PeterShanxin/MeowWatch/pull/279) contains the isolated Windows implementation at `f5a91035973c7d8f1c2a20a6a5acd1e22fc70c8e`. Its final normal Release build and two rendered pairing/revocation flows pass; physical Android-to-Windows acceptance remains open.
- Desktop PR 279's required hosted Analyze & Test job passes in [run 35066075287](https://github.com/PeterShanxin/MeowWatch/actions/runs/35066075287). The separate existing review-routing workflow failed while attempting to request its PR author as reviewer; no human review is currently requested and this is not counted as an approval.
- Early independent Cast review identified stale-controller ownership, event-subscription retirement, resumed-session source confirmation, last-valid-position recovery and external TV-play quota enforcement defects. These are fixed with regression coverage in the 551-test run. Cast handoff keeps the same room socket/session identity; explicit return restores the phone paused. This is automated controller/channel evidence, not a real-TV result; see [Cast acceptance](CAST.md).
- [Native hosting and purchase job 104705497659](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35068900661/job/104705497659) passes the complete Test Store entitlement-to-unlimited-hosting funnel, including cancel/failure preservation, real restore, and two additional distinct Plus sessions after consuming the one free session. Its two native decoders/TLS clients share one Android process; service reopen is not OS process-restart evidence. The separate native Test Store, Nearby, playback and all five production-layout journeys pass again at `f90b85a`.
- Early share/appearance review found a cold-intent delivery race and an upgrade-navigation race. Both are fixed with bounded native queuing and a single owner for the upgrade transition. Native cold/warm SEND/VIEW acceptance is wired into the normal-install gate. MainApp confirmation, cancellation, temporary grants, dual app-links delivery and onboarding deferral have widget coverage.
- The normal release install at `f90b85a` exposed RevenueCat's refusal of Test Store keys in non-debug builds. Release/profile defaults now have billing unavailable, and the service blocks an explicit Test Store key before native configuration. The normal debug APK remains the Test Store judging build. A commercial Play build requires a platform public SDK key.
- The dual-device `f90b85a` run failed in its second pause round. A reachable buffering/toggle bug is fixed: the UI and controller use accepted room play intent while the native decoder reports buffering. The test now confirms local pause before announcing it to the peer. Recorder diagnostics collect both devices even when one clip is missing, and the phone AVD has 3 GB RAM after observed Android memory pressure. The subsequent two-device runtime job in run 35074802807 passes; full production-UI rehearsal remains.
- SAF run `35068900620` searched Recent, whose index did not contain the fixture pushed into Downloads. The runner now navigates DocumentsUI's actual Downloads root and still requires the exact filename. The production-UI two-device run stopped before app launch because its 600-second recording request exceeded the old 360-second runner limit; the bounded limit and its contract now agree. Neither failed run is acceptance evidence.
- P1 integration includes three persistent appearances, entitlement-gated Movie night reactions, peer-link review, Android Share/Open, real recent-room history and a fresh-session Watch together again action. About includes current-version notes. Focused rendered layout and behavioral tests cover these additions; their final native checks are in progress.
- The 54 Python install/share/SAF/lifecycle/compositor contracts pass. Normal APK gates now distinguish debug Test Store from release with billing unavailable. A separate native lifecycle gate checks HOME/foreground, explicit replay and a new Android process resuming saved media; native execution is still pending.
- General webpage extraction has been evaluated against the specification's explicit non-goal of a mobile yt-dlp port merely for desktop parity. Android embeddings are technically possible; the desktop executable provisioner is not portable. This build retains direct-media/file support and actionable failures, with exact limits documented in [Media source support](MEDIA_SOURCE_SUPPORT.md).

## Prior accepted native checkpoint: `f8fdd62`

These passing runs establish the earlier five-layout and independent two-AVD
baseline. They do not supersede failures at the current `feaeb77` checkpoint.

- At `f8fdd626`, [Check 35191578017](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35191578017) passes 631 app tests, 76 TLS and 14 platform package tests, analysis and runner contracts. [Product journeys 35191578190](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35191578190) pass all five native layouts with 45 screenshots and 16 steps each. Original phone/tablet recordings visibly change across onboarding, local playback, Continue Watching and Appearance; inspected small-phone paywall and landscape-tablet UI have no observed clipping.
- [Runtime matrix 35191578138](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35191578138) passes independent two-AVD play/pause/seek/reaction/presence, native Test Store cancel/failure/success/restore, and two distinct Plus-hosted sessions after consuming the free session. Sampled paused positions differ by 299 ms and 256 ms; reported `driftMs: 0` describes pause stability, not zero inter-device offset. Original segment gaps remain visible in the approximate-timeline development composition.
- [Playback 35191578081](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35191578081) passes native progress, seek and reopen on API 35 Pixel 6 x86_64. Its original 43.696-second recording decodes fully and has increasing frame timestamps. Frames after both screenshots continue moving, confirming surface recovery in this run. [SAF 35191578069](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35191578069) passes actual DocumentsUI selection and process restart (PID 3695 to 5101), retaining the permission and 8000 ms resume point. Nearby and same-customer RevenueCat process-relaunch gates also pass at this commit.
- Four full-rehearsal jobs failed at `f8fdd626`: normal debug install stopped on ActivityManager's draw-wait timeout (API 35 already displayed onboarding; API 29 still showed splash), lifecycle preparation was covered by a Pixel Launcher ANR, production Together selected both nested scroll views, and the production purchase driver's diagnostic string touched a disposed widget after cancellation. Release install passed. Subsequent install and purchase success is recorded above; lifecycle and Together remain open with newer failures. This older partial purchase recording reaches cancellation but does not prove its later purchase/paid-host steps.
- Final icon direction A / Balanced has native launcher, splash and in-app evidence; the [brand kit](BRAND.md) and [1200 x 800 Devpost cover](../assets/submission/README.md) are prepared. The [submission compositor](../tools/submission_demo/README.md) passed 13 contracts including actual ffmpeg rendering and timing-offset pixel checks. Its initial contract render was visibly synthetic test footage; later native preview edits do not yet complete the final under-two-minute film.

### Earlier checkpoints

- At `1d5460d`, the final flat cat/play branding passes the normal API 29 debug install and pre-Android-12 splash path, API 35 release install, and all five native product-layout journeys. The API 29 splash/onboarding and API 35 phone home were visually inspected. The API 35 debug install was interrupted by a Google SDK setup ANR; that job remains failed until a fresh run succeeds.
- [Product runtime run 35188550993](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35188550993) passes the two-independent-AVD play/pause/seek/reaction matrix and the real RevenueCat-to-unlimited-hosting funnel. Its separate billing-dialog job failed because a Google SDK setup ANR obscured the valid Test Store purchase dialog; no purchase button was clicked in that failed job.
- [RevenueCat process relaunch run 35188550989](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35188550989) passes actual cancellation, failed purchase, successful purchase and restore. The original PID 2795 is gone before PID 4633 starts; customer hashes match, and Plus remains active after cache invalidation and real SDK restore. This proves process restart with the same persisted customer, not recovery after uninstall or lost identity.
- The `1d5460d` production Together rehearsal reaches secure create/join and peer presence, then fails because the tablet roster is a lazy ListView child below the first viewport. A local 1280 x 800 reproduction confirms that scrolling exposes the peer name. The driver now gestures to the roster and requires the name to be visibly hit-testable before recording its checkpoint. The production purchase driver also now recognizes the actual portrait Play/Pause tooltips.
- Continuous native footage exposed a separate test-capture issue: leaving Flutter's screenshot ImageView active can freeze externally recorded frames while Dart assertions continue. A shared capture helper now converts only around each screenshot and restores the normal surface afterward; its four ordering/failure-cleanup contracts pass. Fresh Android footage must confirm moving frames between captures before final demo editing. Earlier assertion results and screenshot evidence do not establish continuous-video freshness.
- Native recording, SAF and lifecycle failures have narrow runner fixes pending re-execution: probe MP4 creation after Android shared-storage initialization; dismiss only the precisely identified emulator Launcher ANR covering DocumentsUI with retained evidence; retry bounded read-only UI observation timeouts without repeating uncertain input actions or weakening playback thresholds.

- At `6701002`, clean-checkout debug/release install, SAF grant persistence, Nearby and all five product-layout journeys pass. The two-independent-AVD runtime job in [run 35074802807](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35074802807) passes both play/pause/seek rounds, reaction and peer presence; the host consumes one free session and the guest consumes none. Each device has two retained native recording segments. Segment rotation has gaps, so concatenated presentation footage is not quantitative synchronization evidence.
- The same run's one-process, two-decoder hosting preflight fails because controller initialization resets the global audio-mixing option. Mixing is now explicitly requested by those test targets while production keeps normal exclusive audio focus. Its strict pause/convergence assertions are unchanged; fresh native execution remains required.
- Normal lifecycle run `35074802940` exposes a measurement error: the old pre-HOME sample precedes a slow screenshot. A new sample is taken immediately before HOME, with the original four-second tolerance intact. The failed run is not counted as lifecycle acceptance.
- Playback run `35074802824` passes all native decoder assertions, but recording starts before Android mounts shared storage. The recorder now waits for its owned output directory; the missing recording keeps that run failed.
- Production two-device run `35074803021` fails when Dart sends chunked JSON to the bounded rendezvous server. Both requests now send explicit UTF-8 byte lengths, with a real socket regression. Complete MainApp create/join/social footage is still pending.
- The next normal-install gate also checks cold/warm room invitations through VIEW and SEND. A new MainApp purchase journey covers quota paywall, native Test Store cancel/failure/success, Settings restore, a paid theme and two further hosted sessions, with native 1179 x 2556 screenshots. These new gates are awaiting Android execution.
- Independent purchase review found that Settings could show a successful restore when cached Plus remained active after a failed SDK restore. The UI now reports the operation failure while preserving the valid entitlement, with both configured and lazy-configuration regressions. The new native gate checks precise cancellation/failure SDK codes, hashes customer identity, and validates actual recording duration and coverage. Its restore evidence is explicitly limited to calling real SDK restore for the same active customer; lost-access or reinstall recovery is not yet established.
- The dual-device presentation now places each original segment on the host ADB command timeline. Missing intervals and the shorter recording tail are visible gaps, with approximate timing and source hashes retained. This presentation does not establish frame-level synchronization and includes development harness UI.
- A second early product audit found four user-facing defects: missing endpoint details in the visible invite code, prose that made the app's own shared invite fail SEND intake, rediscovery of a saved room onto a later server, and peer commands restarting a background phone. These are fixed with 48 passing focused controller, Cast, Nearby, lifecycle and invite tests. Phone playback requires an explicit Play after returning; Cast remote controls and Nearby lease release retain their existing behavior. Fresh native verification remains required.
- The owner's preferred cat-and-play icon has three close flat refinements, with A / Balanced selected. The reproducible [brand kit](BRAND.md) includes opaque 1024/512/256 PNGs, vector masters, seven-size desktop ICO, simplified small icons and Android adaptive/themed resources. Export hashes, dimensions, ICO decoding and the adaptive safe circle pass. Home/onboarding/About use the new mark; fresh widget-rendered phone/tablet home images have been inspected. Actual launcher/splash checks remain part of the next Android install run, including API 29.
- A standalone RevenueCat relaunch gate now purchases with the real Test Store, records and terminates the original Android PID, installs a same-customer relaunch APK without clearing data, and verifies a distinct process and real SDK Plus/restore after cache invalidation. Its 36 Python billing-driver contracts pass; native execution is pending. This does not claim reinstall or lost-identity recovery.
