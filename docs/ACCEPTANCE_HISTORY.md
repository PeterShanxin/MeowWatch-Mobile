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

## Historical d946d1b cohort and ec856b5 preparation

## Current baseline and isolated SDK comparison

The completed baseline cohort is associated with PR source head
`d946d1bc1ad9fb3cba2c9b3ba17199bad4b9da52`: **6 passing, 4 failed and 1 cancelled
workflow**. Cancelled runs are neither passing nor failed acceptance. Native
results use Android emulators; no candidate result or artifact is silently
substituted for baseline evidence.

The baseline five-layout job actually checked out synthetic PR merge
`d9961f4f52e3e66c775e473c512c0bc2f8722ada`, while the manually dispatched candidate
checked out branch commit `d946d1bc1ad9fb3cba2c9b3ba17199bad4b9da52`. Both have source
tree `5bd55dda62f7827ad517fceedfa42c3af667dc12`. They use different SDKs and produce
different artifacts; matching source trees do not make the APKs interchangeable.

### Passing baseline evidence

- [Check 35219098640](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219098640)
  passes **656 app, 76 TLS and 14 platform tests**, formatting, analysis and the
  checked runner contracts. Gitleaks reports zero findings at the source head
  above, covering 465 tracked files and 43 all-ref commits.
- [Playback 35219098556](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219098556),
  [SAF relaunch 35219098707](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219098707),
  [Nearby 35219098609](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219098609)
  and all jobs in [matrix 35219098750](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219098750)
  pass within their existing emulator/transport boundaries.
- [Purchase 35219098642](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219098642)
  passes all **12 stages and 12 screenshots**: one free host, quota paywall,
  native Test Store cancel/failure/success, same-customer restore with cache
  invalidation, Glass Aurora, peer-received premium reaction, Cinema Noir and
  two distinct paid hosts. All three sessions have real native advancement and
  peer-observed play. This is one API 35 native player plus a headless TLS peer,
  not two filmed players or a real charge. The screenshots were visually
  reviewed; its three raw recordings decode and remain separate segments.
  Do not carry over the different `9b7e9ed` recordings' hashes or gap values.

### Remaining baseline failures and cancellation

- [Install 35219098539](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219098539)
  passes debug API 29 and release API 35, including accepted URL/content sharing.
  Only debug API 35 fails: its native observer cannot obtain the complete tree
  needed for the remaining incoming-media assertion. This is not evidence that
  the already observed media playback failed.
- [Lifecycle 35219098578](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219098578)
  observes real playback advancing from 17 to 28 seconds, then correctly rejects
  a recording that misses its measured tail. The old metadata-validator problem
  is not the current failure. No product lifecycle conclusion or HOME/resume/
  restart pass follows from incomplete recording coverage.
- [Baseline product journey 35219098711](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219098711)
  passes **3/5 complete drivers**: small phone, portrait tablet and landscape
  phone. Phone and landscape tablet both record all 20 app steps and 14
  screenshots, then return driver failure on Flutter `object.dart:6670` during
  teardown. Their successful app-step records do not override driver failure.
- [Baseline Together 35219098687](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219098687)
  passes readiness and native ANR guards, reaches basic two-way playback/social,
  actual shared-link playback and the visible 404 error, then fails recovery
  Play with `object.dart:6670`. It does not prove subsequent recovery/replay.
  Its final phone segment contains one frame with zero duration and fails the
  compositor; no complete paired-film acceptance is claimed.
- [RevenueCat relaunch/expiry 35219098758](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219098758)
  was automatically cancelled by the new PR push. It is not a new expiry pass
  or product failure. The latest accepted expiry remains
  [35212468121 at 9b7e9ed](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468121):
  real Test Store expiry, fresh SDK inactive entitlement and restore remaining
  inactive for the same customer. No lost-identity/reinstall recovery is implied.

### Candidate evidence and current diagnostic runs

[Candidate product journey 35219122572](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219122572)
passes **5/5 complete native layouts** with the same application source tree.
It uses a disposable Flutter 3.44.0 SDK copy with the pinned, still-unmerged
semantics patch from [Flutter PR #190431](https://github.com/flutter/flutter/pull/190431),
commit `65e4783d8a1019029da88ee2435892ef638a9937`. The preparation receipt verifies
unchanged source SDK hashes and the candidate output hash; the upstream
regression also passes. This establishes the candidate run's result, not SDK
adoption, a baseline five-layout pass, or a general fix for all native failures.

[Candidate Together 35219125461](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35219125461)
fails before media because fixed participant names collide on the public server.
It never reaches the recovery boundary and cannot support a conclusion about
whether the candidate fixes `object.dart:6670` there.

Head `d3592795b724d7e8ef9e2a33245f1be8d91f12c1` makes acceptance participant names
unique per run; application code is unchanged.
[Check 35221322293](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35221322293)
passes. The candidate repeat
[35221336722](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35221336722)
exposes another harness mismatch: the public server truncates the longer names
to 16 characters. The next revision uses 15/16-character role names; a direct
production-client TLS probe confirms that both requested names survive login
unchanged. Full paired validation remains open.
Other duplicate native runs from that push were explicitly cancelled while
diagnosed harness issues await correction; they add no acceptance result.

Historical checkpoints, original demo-source provenance and earlier test counts are retained in [Acceptance history](ACCEPTANCE_HISTORY.md).

## Current local corrections and review artifacts

The native observer now retries temporary incomplete roots within one bounded
UiAutomation connection and retains classified failure evidence. Its protocol-v2
helper compiles and verifies against Android API 35; the combined observer,
incoming-media and lifecycle contracts pass 101 tests. Fresh Android execution
is still required. Recording corrections validate original frame timestamps;
single-frame segments without duration remain explicit gaps in review edits.
The lifecycle journey retains restored-pause stability checks before a new
explicit Play action, then verifies actual advancement in the same process.
This leaves the final recording boundary on genuine playback rather than
requiring duplicate frames from a correctly static paused screen.
The compositor and submission editor pass 30 integrated contracts, including
schema-v3 timing and rejection of an untimed still as submission footage.

The desktop companion at `f5a91035973c7d8f1c2a20a6a5acd1e22fc70c8e`
also builds from a new detached checkout with locked dependencies and official
Flutter 3.47.2. The complete unsigned Windows x64 Release review package includes
an isolated-profile launcher, licenses and file hashes. This is build evidence;
native-window and physical Android-to-Windows LAN acceptance remain separate.
[Desktop PR #279](https://github.com/PeterShanxin/MeowWatch/pull/279) remains draft.

## Archived September 24 verification chronology through `85956cb`

This is a preserved historical status snapshot, including then-pending runs.
Use [STATUS.md](STATUS.md) for current conclusions.

## Latest targeted native verification

The September 24 transport/startup revision `773d41e` passes **748 app tests with zero
skips**, formatting of 179 Dart files, analysis and a normal debug APK build on
official Flutter 3.44.0.
The independent Nearby package run passes **87 tests with zero skips**, including
real TLS on the explicit Windows WSL virtual adapter. Both Syncplay and Nearby
retain the underlying connection during a pending TLS handshake so timeout,
leave, replacement and shutdown can close it. Strict certificate trust or pin,
validity and ALPN checks remain intact. Real TLS regressions cover silent peers,
late completions, 8 MiB of backpressure, cancelled flushes, final receipts and
fully drained leaving notifications. Independent review found a dropped leaving
notification during early close; three real TLS regressions reproduced it and
pass after the fix. Transport errors during STARTTLS still reconnect; malformed
answers and failed certificate validation remain terminal refusals.

Initial remote Play now measures actual native position advancement before one
bounded catch-up seek. It also covers source loading into an already playing
room and Local-to-Together adoption. The watch follows its accepted playback
intent; pause, source replacement, connection loss and disposal invalidate it.
Explicit remote seek while already loaded does not add this startup correction,
and corrections do not echo a new user seek. The delayed-start reproduction
fails before the patch; all 28 bridge tests pass afterwards. Both independent
review findings are resolved. Native radio-outage and paired-playback acceptance
still require fresh runs of this revision; these local tests do not establish
physical Android, LAN or Cast behavior. Fresh native verification runs are
`35972090941` (radio loss/recovery), `35972094368` (Nearby Android transport), and
`35972097694` (production phone/tablet Together journey), all at `773d41e`.

The September 24 local verification on an isolated official Flutter 3.44.0 SDK
(Dart 3.12.0) passes locked dependency resolution, formatting, analysis,
**731 app tests with zero skips**, and a normal debug APK build at `1008fff`. Same-host Nearby
TLS tests use the actual Windows WSL virtual adapter; this is not physical LAN
acceptance. The short-landscape join regression now keeps both the editable text
and full error visible above the keyboard, with accessible and pointer-drag
dismissal retained. Fresh five-layout native run `35258088967` passes at
`af45d24`, including independent review of all 80 images and five fully decoded
original videos. Actual native footage confirms the input and error remain
above the open keyboard in short landscape. Independent
review also reproduced stale fullscreen Retry callbacks overriding a later entry
or replacement room; revision/lifecycle guards and owned-notice cleanup fix that
case, including preserving unrelated queued app messages. All 21 immersive
platform/widget tests pass, including the combined paused/accessibility/play/
input-modality regression. A fresh Gitleaks 8.30.1
scan at `1008fff` finds no secrets in 507 tracked files or 93 reachable commits.

That full check includes the input-modality fix below. The test-only
native observer separates bounded cold startup from its
hierarchy budget, propagates caller deadlines through fullscreen/system-dialog
checks, and rejects late results. Its Android SDK 35 APK builds and verifies;
189 related Python tests and another 53 network/audio-interruption tests pass.
Fullscreen auto-hide now captures an observer-free native interval for explicit
image/video review, because accessibility reads themselves reveal the controls.
Fresh phone/tablet fullscreen run `35958877057` at `8290c61` fails: the phone
passes native landscape playback and first Back restoration, then its static
Home transition fails live recording readiness. The finalized third MP4 fully
decodes and visibly reaches Home, but the fresh Home hierarchy gate was never
executed. The tablet times out during the post-idle observer capture. Both
phone idle PNGs still show controls; auto-hide is not verified by this run.
Both tablet idle PNGs also retain controls across 17.92 device seconds, while
the native picture and timeline advance. These failures are not accepted as passes.
The tablet's first post-idle capture now has one 35-second caller budget to
accommodate the observer's existing bounded cold setup/traversal/transfer; late
results still fail and actual two-second native advancement remains mandatory.
The third phone segment now verifies a finite, finalized Home transition, with
fresh Home UI/PNG evidence and explicit manual video review instead of claiming
continuous video over a static screen. All 195 related Python contracts pass.

A separate widget regression reproduces controls remaining visible after keyboard
focus switches to touch without moving focus. The player now tracks focus and
input modality independently, resumes timed hiding on touch, and reveals controls
when keyboard navigation resumes. All 18 fullscreen widget tests pass, including
dynamic accessibility disable and keyboard/touch/keyboard navigation. This is a
confirmed product fix, but its relationship to the native auto-hide failure still
needs a fresh phone/tablet run. Full app verification passes; native run
`35961400943` tests `c142a9e` with the preceding four-second observer budget.
It fails both profiles at native recording-duration validation after pausing:
the phone before fullscreen and the tablet after native fullscreen pause.
The original files have matching device/pulled hashes; static paused frames
stop updating during the recording tail. This is not accepted as complete
fullscreen coverage. The tablet's two idle screenshots still show controls
across 14.07 device seconds (timeline 0:32 to 0:43), so the widget fix does not
establish native auto-hide. That behavior is under separate diagnosis.
The strict moving recordings now finish at phases 04 and 09 while playback is
still advancing; subsequent native pause and stable-position checks retain
fresh hierarchy, window and PNG evidence. No static tail is padded, no duration
tolerance is relaxed, and all 200 related native tool contracts pass. Run
`35965648994` at `1008fff` enables opt-in, fixed-field fullscreen diagnostics
in the normal release entry point. These logs report accessibility, focus,
pressed state and timer decisions without URLs or user content. It is a
diagnostic run; default builds keep the flag disabled, and final native
acceptance still requires a normal build plus original-image/video inspection.
The phone completes the automated journey, but both original idle PNGs still
show player controls across 11.52 device seconds. The diagnostic isolates
17 timer cancellations in that interval: buffering-end reports a transient
not-playing snapshot before the native playing update, and the target getter
mistakenly exposes that as paused intent. Accessibility, keyboard focus and
pointer holds are false throughout those cancellations. Revision `6829cc7`
returns the already maintained play intent through this transition, retaining
true native pause, explicit pause, completion and error behavior. The new
event-sequence regression fails with the old getter and passes with the repair
on the pinned Flutter 3.44 SDK; 315 affected sync/player/fullscreen tests and
scoped analysis pass. An earlier worker test used the wrong SDK; its automatic
dependency/configuration changes were reverted, locked dependencies restored,
and those results are not counted as pinned-SDK verification.
The tablet's first diagnostic attempt stops at phase 04 because its original
native H.264 recording contains a corrupt frame. Device/pulled SHA-256 matches,
and an independent local full decode reproduces the same macroblock error.
The original failure is retained; the separate tablet retry completes the
automated journey, but its idle-control images still require review. Fresh
normal-build phone/tablet run `35968302290` tests `6829cc7` with diagnostics off.
The tablet completes its native journey and independent original-image review:
both 2560 x 1600 idle PNGs hide the player controls and system bars across
19.01 device seconds. Original recording frames cover both observations, and
the three files fully decode. Native states and screenshots verify Back to the
normal player, then Home in the same process. The short third recording starts
after Home appears, so it does not itself prove the full Back transition.
The phone stops before fullscreen at phase 04: a two-second live-file read
timeout aborts the eight-second post-roll window, leaving the last video frame
3.896 seconds before the required observation. Revision `2184c8e` retries the
same read-only byte range within the unchanged deadline, discards partial
timed-out output, rejects late results, and retains the full original-frame
coverage and decode requirements. All 201 related Python tests pass. Normal
phone/tablet run `35969876422` at `2184c8e` now reaches fullscreen on both
profiles. Independent review of original PNGs verifies hidden player controls
and system bars across 12.94 phone device seconds in landscape and 18.64 tablet
device seconds. All four original MP4s fully decode and their frame clocks cover
the required observations. Both runs stop before Back at phase 09: the 90-second
fixture naturally finishes before the fresh Pause-control check. Failure images
and XML show Play at 1:30/1:30 with the same app process. Revision `85956cb`
extends only this workflow's reviewed fixture to 180 seconds. Fresh normal-build
run `35972199031` retains all pause, recording, orientation and Back criteria.

Network run `35958879510` at the same head captures a fresh app hierarchy but
fails before playback or radio interruption: Dart sees the acknowledgement path
before the shell has written its payload. Publication now writes a unique sibling
temporary file and atomically renames it, with exact readback and owned cleanup.
The unchanged Dart exists/read protocol passes a real POSIX interleaving regression
that pauses the writer midway. All 35 network tool tests pass on WSL; a fresh
native run `35960629684` at `ad05764` passes both atomic acknowledgements and
initial native playback, then fails the complete hierarchy read before any radio
is disabled. The helper spent 4.397 seconds from service readiness to rejection,
including 3.388 seconds traversing 28 nodes. No outage/recovery credit is claimed.
The tool's self-imposed hierarchy budget is now eight seconds (startup remains
20 seconds, result transfer two, overall cap 30); incomplete/late evidence still
fails and playback/sync thresholds are unchanged. This is a test-tool latency
allowance, not an application performance fix. Its API 35 helper APK builds and
195 native tool tests pass. Run `35962027407` at `efeff83` fails before any
radio is disabled: four missing-root reads end 449 ms after service readiness,
with the original app PID still focused. Retries now remain in that same
connection for at most sixteen attempts 500 ms apart under the existing
eight-second capture deadline. XML, freshness, PID, playback and sync criteria
are unchanged. Fifty observer contracts, 35 network contracts on WSL and 21
audio-interruption contracts pass; the API 35 observer APK builds and verifies.
Run `35964554315` at `0fdb054` then reaches initial two-client playback and
really disables both radios. A socket error is handled by the reconnect
listener but also escapes into the test zone; the drive subsequently stops
and uninstalls the app, causing the later observer PID-integrity failure.
Revision `fe18041` handles the separate sink completion of both the plain and
upgraded TLS socket, leaving the readable stream as the reconnect owner. A
real loopback TLS abort with queued writes reproduces the unhandled error in
the old client and passes after repair, with exactly one reconnect and no
fixture-side sink error. The native workflow now runs this regression and
STARTTLS refusal tests before building. Run `35968126247` at `6829cc7` passes
those transport regressions but fails initial synchronization before radio loss.
Both native decoders advance about 28–29 seconds; the guest remains 1.025–1.897
seconds behind and never satisfies the unchanged less-than-one-second gate.
All 96 native-read records are accepted. Sequential host/guest reads underestimate
the host's lead, so this is not sampling skew. The first guest Play applies an
older received position after native startup; the established steady-state
follow policy does not correct this small lag. A guarded, one-time startup
catch-up is under implementation. That run retains both original radios enabled;
it does not exercise outage recovery. In the preceding failed run, no network-disabled
acknowledgement or offline/reconnect assertion completed. Cleanup independently
verifies restoration to the original Wi-Fi=false/data=true state. This is not
an outage/recovery pass.

Four additional Bash contract tests verify the
optional Together Profile build/drive mode, APK identity checks and default Debug
behavior. The first Profile dispatch stops before building because existing
fixture tests lacked the new APK provenance inputs; those fixtures are corrected,
all 69 related tool tests pass. Run `35960861121` at `511eed6` builds both
Profile APKs but fails before media: the host times out waiting for peer
presence and the guest times out waiting for its secure-room connection.
Profile is a motion diagnostic, not purchase or Debug acceptance. No motion
improvement is established by that run. Native footage and the pinned Flutter
source isolate a test-input defect: Profile drops the debug-only text-input
client ID, leaving the guest room field empty. The test-only helper now uses
the focused EditableText input path in Profile and verifies the actual text
before submission; Debug retains normal tester text entry. Three regressions
pass, including normal input formatting/validation and rejected read-only
entry. This does not establish physical IME behavior. Profile diagnostic
`35965651942` at `1008fff` passes 26 host and 25 guest named steps, both
drivers and teardown, with unchanged join/play/chat/presence assertions and
the compact native capture configuration. Original footage still contains a
6.546-second tablet frame gap during requested playback. Functional success
does not establish smooth decoded motion; this is not approved as the final
demo recording or evidence of a general performance improvement.
The development showcase recording resumes in a new file; the prior file's last
saved chunk is September 18. The intervening gap is not continuous footage.
The September 24 browser/process later exits after the 06:00 UTC chunk;
a new segment starts at 06:21 UTC. Both originals and the gap are retained.

The fresh PR cohort at `115454e3e93758fd9ef379ac441669bf20b1ab26`
has ten passing workflows and four failures, including
the phone/tablet fullscreen workflow. The actual Actions checkout is merge commit
`e79b6fd5465cc01901758c0ec13d538691e4ce19`; its source tree is identical to
the PR head (`63ee234c6cba54eeb08fab0c96e5319b6f81df90`). This is not a green
whole-product rehearsal. In particular:

- [Foreground audio focus 35250983507](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35250983507)
  passes independent original-evidence review. A separate native helper takes
  permanent audio focus while the normal release app stays foreground at PID
  2982. Playback pauses at 55 seconds, stays there through release, and advances
  only after explicit Play. Ten window/lifecycle snapshots, fourteen successful
  native UI captures and both fully decoded recordings agree. This covers Local
  mode on one API 35 x86_64 emulator, not calls, transient focus, room continuity
  or physical audio output. Preparation included one verified Launcher ANR
  recovery; the full focus scenario starts afterward.
- [RevenueCat relaunch 35250983385](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35250983385)
  passes independent audit of all four drivers and their teardown. The same
  customer survives PID `2407 -> 4693` without data clear or uninstall. Eight
  expiry observations include fresh inactive data at 17:23:51.659 UTC on
  September 17 and cache-invalidated Restore still inactive at 17:23:51.755.
  This run observes the first five-minute period, not the previous run's
  twenty-five-minute renewal history. All three native Test Store recordings
  and six PNGs decode; the videos do not continuously cover relaunch or expiry.
- [Fullscreen 35250983436](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35250983436)
  renders the normal release phone app in actual landscape, but its first-entry
  gate stops at Android's `ImmersiveModeConfirmation` tutorial. The retained
  screenshot and native hierarchy show the system's **Got it** button over the
  fullscreen app. A narrowly identified native acknowledgement is implemented;
  the remaining playback/Back assertions have not passed yet.
  The tablet fails earlier during preparation with an ADB shell exit, before
  recording any application observation; its failed-run screenshot is black.
  The exact command failure was not retained. Emulator-action cleanup then
  stalls until the job deadline; no tablet fullscreen coverage is claimed.
- [Network 35250983455](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35250983455)
  fails before radio interruption: the second native player does not advance.
  Both TLS clients connect, but the recording does not establish why playback
  stalls. Failure diagnostics are being expanded; no outage or recovery result
  is claimed.
- [Install 35250983373](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35250983373)
  passes debug API 29/35; release API 35 is blocked by a late Google SDK Setup
  ANR over the rendered onboarding screen after a successful app launch. The
  runner's existing exact recovery did not cover that timing.
- [Lifecycle 35250983364](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35250983364)
  observes initial native playback advancing, then correctly rejects a corrupt
  H.264 recording before HOME/relaunch. This run supplies no new lifecycle
  acceptance; the original damaged file remains available for diagnosis.

The next targeted [fullscreen run 35253732711](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35253732711)
at `934b20f` supplies fresh phone entry proof: the same PID 2684 changes from
1080x2400 to 2400x1080, rotation 1, with both actual Insets sources hidden and
the paused position still at 16 seconds. The exact first-use acknowledgement
was exercised. Its original fullscreen PNG was visually inspected and added
unchanged to the live showcase as captured evidence. The run subsequently
fails the second recorder's live readiness before Play; its finalized 13-frame
MP4 decodes completely. Sample order and Android's MP4 chunking behavior support
a static-screen recording wait, not a proven encoder or orientation failure.
The tablet reaches the loaded player but its native observer times out during
the next snapshot, before entering fullscreen. Complete playback/Back acceptance
on both form factors is still pending.

The next [fullscreen run 35259390763](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35259390763)
at `a49e458` passes live recorder startup on both devices, including the phone's
landscape segment. The phone again retains PID 2633, its paused position at
48 seconds and hidden system bars on entry. It then fails the control auto-hide
assertion. That assertion uses an accessibility observer; investigation shows
the observer can activate the production accessibility behavior that deliberately
keeps controls visible. This is not yet a completed auto-hide or Back gate.
The tablet's first playback snapshot hits three observer startup timeouts before
any hierarchy traversal. Its failure PNG visibly shows native playback at
27 seconds, but the required observation is missing. The original tablet video
fully decodes and matches the finalized device hash. Both jobs remain failed;
recorder startup alone does not approve the complete journeys.

[Normal install 35253861618](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35253861618)
at `54b4203` passes independent audit for debug API 29/35 with Test Store and
non-debuggable release API 35 with billing disabled. All are normal `lib/main.dart`
APKs installed onto package-absent emulators. Each passes seven cold/warm external
entry review-and-cancel cases, plus explicit HTTPS/content-URI playback. Those
two elapsed positions advance by 3/4 seconds on debug 35, 2/4 on debug 29 and
6/5 on release 35. Three APK hashes match their own install receipts; all 42
original PNGs validate and three first-launch MP4s fully decode. API 29's launch
wait times out, then exact rendered first-use UI and the stable process pass.
The new late SDK Setup ANR branch is not exercised in any job. Temporary media
cleanup and emulator shutdown have positive receipts. All three APKs use debug
signing; this is not physical-device, actual purchase or Play signing acceptance.

[Network diagnostics 35253823599](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35253823599)
at `1d76cea` reaches `initial-ready` with both native players advancing. The old
second-player startup failure does not recur. The native observer then returns
four `root_missing` results with zero visited nodes while MainActivity and PID
3061 remain unchanged. Radio interruption is not reached. The interrupted driver
does not retain a final result or complete teardown; missing fields are not
counted as successful assertions. Fixed-stage observer diagnostics are being
added without changing its time limits or complete-hierarchy requirement.

The next [network run 35257388457](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35257388457)
at `3822d19` fails earlier: the host's native `controller.position` read exceeds
its unchanged five-second timeout during initial playback. Its first observer
capture succeeds with 19 nodes; measured root/refresh/traversal stages take
36/4/43 ms. The complete failure and framework teardown are retained. It does
not reach the old run's later failed observation, nor radio interruption.
Per-player native read timing diagnostics are now implemented at `9150f4d`,
with 32 passing Python contracts and clean Flutter analysis. Targeted run
`35260820569` retains the original read and playback thresholds. Its eight native
reads all succeed in 12–640 ms; both players advance and pass `initial-ready`.
The subsequent observer capture fails after three missing roots and a fourth
partial traversal that exceeds its budget. PID 3604 remains focused. Radio
interruption is not reached, and the externally stopped driver has no completed
app teardown. Runner-owned cleanup passes. This does not establish a production
synchronization defect; the incomplete hierarchy remains failed evidence.

[Lifecycle 35256363876](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35256363876)
at `8720304` passes independent original-evidence review. Real HOME retains PID
3103, then foreground playback stays paused until explicit Play. Force-stop
and relaunch produce PID 6073; Continue Watching restores 63 seconds paused,
and the next explicit Play advances 65 to 75 seconds. All 20 observer captures
succeed, including two observations of one exactly identified SDK Setup ANR
during preparation. Both recordings fully decode (330/919 frames), their finalized
device hashes match the pulled and downloaded files, and frame clocks cover
the final observations. The old damaged tail does not recur; its cause is not
established. Restored paused footage shows a delayed one-time bee-to-flower
texture change while time and Play remain stable; immediate frame-exact restoration
is not claimed. Observer removal, fixture-server stop and emulator shutdown have
positive evidence; final app/storage cleanup has no independent raw transcript.
This run predates the later startup callback, storage and observer changes.

A matched manual compact-recording experiment compares
[baseline 35252661607](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35252661607)
at `115454e` with
[fullyLive 35252727231](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35252727231)
at `eefe371`. Only the integration binding's frame policy and its reported
value differ. Product code, assertions, media, native layout and recording
profile are unchanged. Both complete functional audits pass: 26/25 steps,
teardown, native supervision, seven zero-delta synchronization checkpoints and
unchanged session-quota behavior. All eight original recording segments decode
and match their source hashes and timing receipts. Movie-only motion review
finds partial improvements, but the candidate phone still holds the movie for
2.5 seconds during peer control and both clients hold it for six seconds during
recovery. Changing spinner pixels are excluded from this measurement. These
captures are not accepted as the final professional film; the frame policy is
not established as the sole cause or a complete fix.

A fixture-only [Range comparison 35259340609](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35259340609)
uses isolated branch `experiment/range-fixture` at `e3656e9`, based directly on
the prior `eefe371` candidate. App/driver source, media bytes and preparation,
capture profile and assertions are unchanged. The previous stock Python server
returned full HTTP 200 responses; Media3 discards preceding bytes when a nonzero
seek receives 200. The replacement supports single byte-range 206/416 and bounded
request diagnostics, preserving the previous socket timeout behavior. Twenty-three
real Linux HTTP/ownership tests and the focused review pass. Independent artifact
review accepts the complete 26/25-step Together sequence and teardown, with seven
zero-delta position comparisons. All four original recordings fully decode.
Nine complete 206 responses write exactly the requested tail; five cancelled
responses are recorded separately. Recovery movie motion improves, but the
tablet still holds one movie image for 7.728 seconds during initial playback,
including a 3.943-second whole-picture gap. These originals are not approved as
the final professional film. Range support alone does not establish smooth
playback or explain host/decoder/recording contention.

[Runtime matrix 35241701885](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35241701885)
at `6c44e415386e3a39ee3371aed5b6066e9ec9996c` passes all three jobs; original
artifacts and full teardown were independently audited. Two API 35 x86_64
emulators report controller/peer paused positions of 6133/6133 ms and
2538/2538 ms, stable for 1123/1467 ms after convergence in 1927/2305 ms.
Both peer seeks reach 4000 ms paused. The test source is byte-identical to the
failed baseline, including its original tolerances. These are native position
checks, not identical-frame claims; the captured movie frames differ.

The same run passes ten native RevenueCat Test Store checks and fourteen
hosting checks, including one free and two distinct Plus sessions. Hosting uses
two TLS clients and native decoders inside one app process, so service/disk
reopen is not process-relaunch evidence. All nine videos fully decode. The
paired originals have no rotation gap; the phone misses about 0.196 seconds
at the shared timeline's ends. The 88.5-second composition uses a runtime
fixture screen, not the production UI, and is not selected for the submission
film. Original VFR intervals reach about 6.3 seconds; this is not smoothness proof.

[RevenueCat diagnostic run 35240675074](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35240675074)
at `9e032ba6f656a1170a4dbbb05540f03221abdf57` passes the unchanged strict
relaunch/expiry assertions. The same persisted customer survives PID
`2994 -> 4730` without uninstall or data clear. Across eight bounded expiry
phases, 52 fresh observations retain the same customer and show five consecutive
five-minute Test Store periods. The last purchase is 16:01:01 UTC and expiration
is 16:06:01 UTC on September 17. Fresh customer data at 16:06:03.883 is inactive;
cache-invalidated Restore at 16:06:04.040 remains inactive. All ten phases retain
customer-update diagnostics with no within-phase request-date regression.
The earlier 2fc inactive-to-active Restore anomaly did not recur; its cause is
still unproven. No production billing behavior or assertion was weakened.

[Production Together 35243162891](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35243162891)
at `5137e5870f9ac611a339daf42bcd24abfcbb412d` passes 26 host and 25 guest
production steps, retains 14/12 native screenshots, and completes both drivers
and all cleanup. Named pause/seek, shared-link, recovery, history and new-room
position checkpoints have zero reported delta. Both preparation checks require
no recovery; the one-install SDK package preparation and read-only receipt check
run successfully, followed by independent stable readiness admission. This run
does not exercise the new Launcher recovery branch. Native footage shows the
correctly themed loading text. These results do not turn the separate 2fc cohort
green or establish physical-device acceptance.

Paired recording quality remains a film limitation: actual playback windows
retain about 1–3 native frames per second, with visible jumps. The original
clock and gaps remain intact; encoding at 30 fps does not restore missing motion.
A manual compact-capture comparison reduces recorder output size while keeping
the app's display layouts, timing, 3 Mbps bitrate and product assertions unchanged.
Its result must be inspected before replacing these sources in the final edit.

The compact-capture comparison at `694b1ac5e42f431e28209246baf7c3441fcd75df`,
[run 35246511825](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35246511825),
passes both complete drivers, unchanged 26/25 step sets, 14/12 screenshots,
18/18 observations and cleanup. Independent native log/position audits pass.
All three recordings fully decode and match their recorded hashes. The tablet
required one narrowly verified Google SDK Setup ANR recovery before app
installation; both devices subsequently passed fresh readiness admission.
The Launcher recovery branch was not exercised.

The compact capture does not resolve film smoothness. Three actual playback
windows retain about 2.00–4.29 original pictures per second, some reflecting UI
updates while movie pixels remain held. The phone is 432×960 and the tablet
960×600; text remains readable. There is no segment restart, but the phone has
a 2.512323-second missing tail, preserved in the timing manifest. These sources
remain review/evidence material rather than accepted final-film footage.
The earlier 5137e58 readiness log contains a historical GMS SafetyCenter
broadcast ANR before app installation. Later readiness admission and application
checks pass; this is not a claim that the entire OS log is free of ANRs.

A complete **118-second Review Preview** now combines the audited 5137e58
Together footage with 2fc38317 Local and purchase footage. All 3,540 frames
decode and all eleven pinned inputs match; 29 output samples and six full-size
frames were inspected. It retains the low native motion cadence and is not an
accepted submission film or a single-build rehearsal. See [the demo script](DEMO_SCRIPT.md).

The remaining autonomous interruption gates cover actual Android radio/network
loss and recovery, plus external audio-focus takeover while the normal app stays
foreground. Existing socket-reconnect simulation, leave/rejoin and HOME evidence
are not substituted for those cases. Full final-head checks and the clean-install
submission rehearsal also remain open.

The requested immersive player is implemented and awaiting native acceptance: explicit fullscreen,
tap-to-reveal controls and Back-to-exit preserve the current player and room.
The Android window bridge hides system bars and temporarily requests handset
landscape; tablet orientation is retained. The bridge and room/chat widget
regressions pass all 67 checks, including 13 fullscreen cases. The integration
APK containing the native bridge and the normal debug APK both build
successfully. The integrated local suite passes 719 tests with no skips,
formatting checks 175 files without changes, and analysis reports no issues.
The LAN test uses the host's real WSL virtual adapter, not a physical phone.
Native phone/tablet window-state proof is still open; the earlier landscape
layout evidence does not prove immersive mode.

## Completed native cohort: 2fc38317

The completed source head is `2fc38317f96efa2b15239b6be3dfedce9264987c`:
**8 passing and 3 failed workflows**. These results use Android emulators;
they do not establish physical hardware acceptance. Later diagnostic or
presentation commits do not inherit this cohort's results.

| Workflow | Result | Acceptance boundary |
|---|---|---|
| [Check 35236920596](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920596) | Pass | Formatting, analysis, 697 app tests, 76 TLS tests, 14 platform tests and required tooling contracts |
| [Playback 35236920494](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920494) | Pass | Native Android playback |
| [Nearby 35236920513](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920513) | Pass | Emulator companion boundary; physical Android-to-Windows LAN remains open |
| [SAF relaunch 35236920516](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920516) | Pass | Native DocumentsUI selection, persisted grant and restart playback |
| [Production purchase 35236920484](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920484) | Pass | 12 stages, three real hosted sessions and actual Test Store purchase/restore |
| [Normal lifecycle 35236920517](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920517) | Pass | Normal release APK, HOME/no-autoplay, explicit replay and changed-PID history resume |
| [Five layouts 35236920763](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920763) | Pass | Five complete drivers and teardown, 100 app-step observations, 80 PNGs and five native videos |
| [Normal install 35236920483](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920483) | Pass | Debug API 29/35 and release API 35, including real incoming-media playback |
| [Together 35236920607](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920607) | Fail | Pixel Launcher ANR before app installation; zero app or paired-video coverage |
| [Runtime matrix 35236920487](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920487) | Fail | Real stale paused-position snapshot; later 6c44 fix passes targeted native validation |
| [RevenueCat relaunch/expiry 35236920647](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920647) | Fail | Fresh inactive observation followed by active Restore; later diagnostic run passes without reproducing or explaining this anomaly |

### Audited install, lifecycle and rendered UI

All three normal-install variants pass seven incoming-media review cases. A
valid share stays on its review screen until explicit Open, then loads a
52-second HTTPS or content-URI video paused at zero until explicit Play.
Playback advances in every case with stable app PID and exact focus. The six
loaded hierarchies each contain the intentional matching header/body titles;
the body-scoped predicate now passes on actual native evidence. URI read grants,
payload hashes and provider cleanup are verified. Empty Flutter shells are
rejected and freshly recaptured within the original observer budget. The three
1080x2400 first-launch videos fully decode; later intake stages have XML/PNG
evidence, not continuous video coverage.

Normal release lifecycle playback advances before HOME, stays paused through
foreground return and a further four-second hold, then advances only after
explicit Play. Saved position 73 seconds survives PID `2971 -> 5921`, with the
old process absent before relaunch; the restored player remains paused through
another four-second hold before explicit replay. All 13 native states and 17
fresh observer captures validate. The existing four-second allowance immediately
after HOME is reached exactly, not relaxed. No ANR recovery occurs. Readiness
passes without timeouts, so this run does not exercise its new timeout-retry
branch.

Both lifecycle recordings are 432x960 H.264, last 67.870856 and 117.399222 seconds,
and fully decode to 324 and 743 frames. Hashes, original frame timestamps and
coverage of each last critical observation validate. The manifest records a
6.447-second host interval between segments; this is not continuous footage.
The helper is removed after the run. Auxiliary `media.codec` service lookup is
unavailable and is not represented as codec-state evidence.

The five-layout run uses one API 35 emulator resized to phone, small phone,
tablet and portrait/landscape viewports on official, unpatched Flutter 3.44.0.
Every driver completes all 20 app steps, 16 PNGs and teardown. Original logs show
no framework geometry assertion, RenderFlex overflow or uncaught app failure.
At 1600x720, the compact guide's title, primary instructions and fixed footer
fit; supplemental notes remain scrollable. Actual Settings, Appearance and
paywall transitions were inspected without a stale sheet obscuring the next
destination. All five single-segment videos have verified hashes and complete
decodes; they have no recording restart gaps. This is one successful baseline
cohort, not proof of a general upstream framework fix.

### Audited production purchase

The API 35 purchase journey uses the real MainApp service factory, one native
player and an independent headless STARTTLS peer in the same process. It passes
all 12 verification checkpoints with 12 original 1179x2556 screenshots. Native
XML/window evidence confirms Cancel, Test Failed Purchase and Test Valid
Purchase actions. Cancel and failed purchase report SDK error codes `1` and
`42`; both leave the free ledger unchanged. Success activates `meowwatch_plus`, retries
the original host intent, and supports two distinct paid hosted sessions after
the one free session. Each accepted session has actual advancing playback and
a secure peer observation; remaining free hosts stays at zero.

Cache-invalidated Restore in Settings retains the same SDK customer and active
entitlement. Glass Aurora and Cinema Noir persist through production UI; the
premium Movie night reaction reaches the real TLS peer with the expected sender.
These checks do not establish process relaunch, expiry, lost identity or Google
Play account restore. The separate expiry gate below remains failed.

The three original 480x1040 H.264 recordings last 69.085711, 69.794578 and
17.842956 seconds, decode completely to 298/280/63 frames, and match the downloaded
artifact ZIP by SHA256. Recomputed coverage is 158.254 of 160.060 monitored
seconds (98.8717%), with 1.068- and 0.738-second rotation gaps. Startup and test
teardown are included; this is not a seamless final film. The immutable artifact
ZIP digest is `c8b41c80a47ee92bb2ebaa6b374d1762b9b5d256f3cce27e96007bd7fb860ba2`.

Actual video at segment 1, 34 seconds and segment 2, 27 seconds shows normally
themed **Finding your room...**, its description and Cancel in Cozy and Glass
Aurora, without the earlier red/yellow fallback text. Cancellation and failure
PNGs catch transient catalog-refresh spinners; subsequent original frames at
segment 1, 65 seconds and segment 2, 4 seconds show readable feedback and a
retryable purchase button. Settings/Appearance/theme/room transitions are also
visible in the retained native footage.

### Failed gates and subsequent work

- Together stops before installing MeowWatch because Pixel Launcher owns an
  ANR window. The earlier SDK Setup ANR is a different package; the narrow
  preparation correctly performs no unrelated recovery. No app driver,
  independent readiness admission or paired composition runs. The accepted
  300ca2e Together journey below remains evidence for that older source only.
- The runtime matrix exposes a cached pause position of 3668 ms versus 4109 ms
  after settling: a real 441 ms stale snapshot, not an accepted synchronization
  result. A regression fails on the baseline and the pause-position fix passes
  33 focused local tests. Commit `6c44e415386e3a39ee3371aed5b6066e9ec9996c`
  also passes formatting, analysis, all 704 app tests (including the real-adapter
  cases) and the normal debug APK build. It clamps confirmed positions to the
  valid media range and rejects pause reads superseded by another command.
  [Runtime matrix 35241701885](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35241701885)
  passes all three jobs with audited originals; playback/convergence thresholds
  are unchanged.
- RevenueCat first returns a fresh inactive entitlement, then Restore returns
  active. The retained post-restore data is insufficient to explain that change;
  no renewal or SDK root cause is asserted. The strict expiry/restore assertion
  remains failed. Diagnostic-only commit `9e032ba` adds evidence for manual
  [RevenueCat run 35240675074](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35240675074),
  which passes final expiry and inactive Restore as detailed above. It does not
  weaken expiry checks or prove the earlier failure's cause.

The separate presentation branch at `152330ba39e2c263dea5a5f81e032072869f7016`
has a failed manual [Together run 35238737381](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35238737381):
the Android system-image ZIP fails during preparation, before an AVD or app
journey exists. It contributes no native product acceptance and is not one of
the eleven 2fc38317 cohort results above. Commit
`5137e5870f9ac611a339daf42bcd24abfcbb412d` prepares the SDK once before building
APKs, retains verbose installer evidence and verifies the same installed packages
at launch. It adds one strictly identified preinstall system Launcher recovery;
the independent readiness policy and all app ANR guards remain unchanged.
All 62 multi-device tooling tests and 32 production driver tooling tests pass;
independent code review found no actionable issue. The new official-baseline
[Together run 35243162891](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35243162891)
passes as detailed above. ZIP root cause and Launcher-recovery effectiveness
are not inferred from that run: neither emulator needed recovery. Physical playback/lifecycle/billing,
Android-to-Windows LAN, Cast, remaining eligibility/legal checks, final film and
the complete submission rehearsal remain open.

## Previous completed native cohort: 300ca2e

The source head is `300ca2ea748999a9b5b73d1a2d03c104c2ed2e22`:
**9 passing and 2 failed workflows** by latest CI conclusions, including the
successful second purchase and Together attempts. Together's retained drivers,
native logs and recording evidence have been independently audited. These
results use Android emulators and do not establish physical hardware acceptance.

[Check 35230867540](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867540)
passes formatting, analysis, 682 app tests, 76 TLS tests, 14 platform tests and
the required tooling contracts. CI selects a real same-host adapter for its LAN
cases; those tests do not establish physical Android-to-desktop discovery.

[Five layouts 35230867480](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867480)
passes all five drivers and their teardown on the official, unpatched SDK. Each
has 20 app steps, 16 original screenshots and one complete native recording.
Driver/logcat review found no framework geometry assertion or RenderFlex
overflow. This is one API 35 emulator resized to five viewports, not five
physical devices. Native phone guide/media and tablet Settings/player images
were inspected; the short-landscape guide had not yet received its compact layout.

[Purchase 35230867387, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867387)
passes all 12 stages: one free and two distinct paid rooms, real native Test
Store cancel/failure/success, same-customer restore, saved themes and a premium
reaction received by an independent TLS peer. Both native segments are
480x1040; original screenshots remain 1179x2556. Duration shortfalls are
0.982/0.899 seconds, rotation gap 2.149 seconds, and aggregate coverage 98.46%;
the 3-second, 15-second and 90% limits are unchanged. Attempt 1 failed while
downloading the Android Emulator ZIP, before any app runtime. The successful
comparison does not establish the cause of earlier encoder-tail failures.

[RevenueCat relaunch/expiry 35230867563](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867563)
passes and its retained evidence has been audited. The same persisted SDK
customer survives PID `2964 -> 4960`, with the old process confirmed absent
before relaunch and no requested uninstall or data clear. The Test Store
purchase at 14:11:44Z renews through 14:31:44Z, then expires at 14:36:44Z.
Seven bounded segments retain 49 fresh SDK observations; the first six remain
explicitly pending. The fresh request at 14:36:55.873Z returns inactive, and
cache-invalidated restore at 14:36:56.001Z remains inactive for the same customer,
product and original purchase. Evidence and cross-segment continuity validation
pass. No clock change or dashboard entitlement override supplies the result.

This expiry journey uses the integration-test entrypoint and replacement debug
APKs. Its three 1080x2400 H.264 recordings cover native Test Store
cancel/failure/success only: 13.659, 5.751 and 5.863 seconds. All decode without
errors and have strictly increasing frame timestamps; the recorded purchase
dialog and before/after screenshots were inspected. There is no continuous
relaunch or expiry-wait recording. One Google SDK Setup ANR before Cancel was
retained in XML, window state and screenshots, then closed by the existing
exact-package emulator recovery. Production paywall coverage comes from the
separate purchase journey; physical or lost-customer-identity recovery remains
unproven.

Native [playback](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867384),
[SAF relaunch](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867427),
[Nearby](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867507)
and [runtime matrix](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867651)
also pass. Their emulator boundaries remain applicable.

At that historical checkpoint, two gates failed and their follow-up fixes had
not yet run natively. Both are now accepted separately in the 2fc38317 cohort:

- [Normal install 35230867474](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867474)
  reaches a loaded, paused 52-second video in all three variants. Its old global
  title-uniqueness check rejects the legitimate title in both header and player
  body. The replacement verifies the body title beside its local-target caption,
  still requiring the real timeline, duration, controls, PID and focus. Empty
  Flutter shells are rejected and successfully recaptured within the original
  observer budget. This 300ca2e workflow remains a failed historical run.
- [Lifecycle 35230867465](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867465)
  stops in preparation on a single ADB readiness timeout. No app samples ran.
  The retained recording is valid 432x960 H.264 from `c2.android.avc.encoder`.
  Only readiness-read timeouts may now retry inside the same absolute 20-second
  deadline; late successful reads are rejected, and all recording coverage
  limits remain intact.

[Together 35230867493](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867493)
attempt 1 encounters a Pixel Launcher ANR before app installation. The SDK Setup
preparation correctly refuses to mutate this different package. Same-head
attempt 2 passes on official, unpatched Flutter 3.44.0 and two API 35 x86_64
emulators. Independent artifact audit confirms the phone host's 26 steps and 14
720x1600 screenshots, and the tablet guest's 25 steps and 12 1280x800 screenshots.
Both complete drivers pass. Their retained logs show no framework geometry
assertion, Flutter exception or RenderFlex overflow. Deliberately injected media
404 errors and system IME FrameTracker timeouts remain visible; this is not a
claim of zero log errors or a general fix for the upstream geometry issue.

Named host pause/seek, guest pause and shared-link, recovery, history and
new-room pause checkpoints each record 0 ms peer delta. These are sampled
convergence checks, not frame synchronization. The peer's playable link goes
through explicit confirmation and real decoding in the existing room. A failed
media URL produces a readable error; **Choose another video** restores actual
playback. History Resume preserves each room endpoint and quota ledger: the
original host has 0 free hosts left and the guest has 1. **Watch together again**
creates a new room/invitation with QR rejoining; the original guest becomes host
and spends 1→0, while the original host joins and remains at 0.

Native ANR supervision passes 96 host and 88 guest probes, plus one probe per
device after both drivers. Neither device needs the SDK Setup preparation
recovery; its subsequent read-only admission reports READY after 20 samples and
three consecutive stable windows. Four original native recording segments and
the 1920x1080, 30 fps paired composition have verified hashes. The composition is
216.667 seconds. Its manifest exposes the phone's 1.867-second middle gap and
tablet's 1.667-second middle gap, 0.007-second opening gap and 0.518-second tail.
Alignment uses host command time; this is not seamless or frame-synchronized
footage. The final under-two-minute submission edit remains separate.

Reviewing that purchase footage also exposed a loading overlay outside any
Material text context, producing red/yellow fallback typography. A local fix
adds themed text, scrolling at large font sizes and modal semantics; its
regressions fail on the old app and pass after the fix. The Settings/Appearance
upgrade chain waits for its owned routes to finish exiting. These later changes,
the compact landscape guide and the install/lifecycle harness fixes received
their own native proof at 2fc38317, described above; they do not inherit
300ca2e's results.

That follow-up passed local formatting (182 files), static analysis and a normal
debug APK build on Windows ARM64 with official Flutter 3.44.0. The app suite
passes 687 tests with 10 adapter-dependent tests initially skipped; a separate
11-test run, including one repeated non-network test, exercises all ten against
an enumerated Hyper-V IPv4 adapter. This is same-host pinned TLS, not physical
LAN discovery. The combined incoming/install/observer/lifecycle tooling suite
passes 144 tests. Four font-loaded widget renders confirm the compact guide
and Settings replay; these are explicitly test-renderer evidence. The staged
472-file snapshot and 51-commit history scan report zero secret findings.

## Previous completed native cohort: ec856b5

The baseline head is `ec856b5317f96e9ff1421a96c312ce22dde764fa`:
**6 passing and 5 failed workflows**. All native results here use Android
emulators. None proves physical hardware behavior. The subsequent recovery and
capture fixes are outside that tested head and require fresh native workflows.

Passing workflows are [Check 35223362579](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35223362579),
[playback 35223362914](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35223362914),
[Nearby 35223362515](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35223362515),
[SAF 35223362742](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35223362742),
[runtime matrix 35223362748](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35223362748)
and [RevenueCat relaunch/expiry 35223362820](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35223362820).

The expiry run retains the same customer across PID `2423 -> 4782`, without
uninstalling or clearing data. Its real Test Store purchase at 12:58:32Z expires
at 13:03:32Z. Fresh SDK evidence at 13:03:41.654Z is inactive; cache invalidation
and restore at 13:03:41.704Z remain inactive. This is real five-minute expiry,
not an injected clock. Videos cover the native Test Store dialogs only; there
is no continuous relaunch/expiry movie or lost-identity/Play-account restore proof.

### Failed gates and exact boundaries

- [Clean install 35223362735](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35223362735):
  debug API 29 and release API 35 pass actual URL/content sharing. Debug API 35
  returns two inert native FrameLayouts while its original screenshot still
  shows the shared-video confirmation. It does not prove dialog disappearance.
  The helper now retries this precise incomplete Flutter shell within its
  existing four-attempt/four-second budget; fresh native validation is required.
- [Lifecycle 35223362716](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35223362716):
  real playback advances 7 -> 20 seconds in the same PID. The decoded last
  frame covers the last critical observation but is 7.01 seconds behind stop;
  duration shortfall is 3.91 seconds, exceeding the unchanged 3-second limit.
  The workflow stops before HOME/resume/restart acceptance. The next comparison
  reduces encoded dimensions to 432x960 and adds bounded codec diagnostics;
  it does not weaken timing gates or claim an established encoder root cause.
- [Production purchase 35223362549](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35223362549):
  the first recording spans 70.003 seconds but decodes to 66.654 seconds,
  exceeding the unchanged 3-second shortfall limit. Native cancellation occurred;
  failure/success and the complete product journey are not accepted. The next
  capture comparison uses 480x1040 at the same 2 Mbps; native screenshots remain
  1179x2556. Segment, gap and aggregate coverage gates remain unchanged.
- [Five layouts 35223362621](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35223362621):
  phone, small phone and landscape phone pass. Tablet and landscape tablet each
  record all 20 app steps and 14 screenshots, then fail Flutter geometry teardown
  at `object.dart:6670`. All 70 original PNGs are present. The actual PR merge
  checkout `2502f026293638fe47d464c1666162cbd6bbad4b` and source head ec856b5
  have the same source tree `61ec12d71895c6a1c773286c208d3c8d78389773`.
- [Together baseline 35223362923](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35223362923):
  cold-boot admission fails before MeowWatch installation because SDK Setup owns
  an ANR window. No app journey ran. A separately recorded, tightly scoped
  preparation can recover that exact task-owned emulator dialog once; the
  complete read-only resource/readiness gate still runs afterward.

### Separate SDK experiment and product recovery

[Candidate Together 35223358577](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35223358577)
uses an isolated Flutter 3.44.0 copy with the pinned 14-line upstream PR #190431
candidate. Unique 15/16-character participant names work. The run still triggers
ancestor-identity geometry at `object.dart:6684` during shared-media replacement,
then fails recovery Play. The patch remains **unadopted**; its earlier five-layout
pass does not establish a fix for this different path. A new semantics contract
passes on both SDKs and checks labels, actions, traversal and stable leaf identity;
it is not a bug reproduction or native TalkBack acceptance.

The original recovery screenshot and UI tree establish a separate app defect:
a stale error Snackbar covers the recovered player's Play center. The unmodified
ec856 app fails a new regression because that Snackbar remains. The fixed app
removes only its owned stale notification; message, lifecycle and incoming-intent
regressions pass. Shared-link loads now wait for their own confirmation and phone
chat sheet to finish closing, exposing loading/error UI on the player and refusing
stale room/target/navigation changes. Neither app fix is claimed to solve the
framework geometry assertion before native reruns.

## Historical local verification after ec856b5

Official Flutter 3.44.0 formatting and analysis pass. The full local app suite
passes **672 tests**, with **10 explicitly skipped adapter-dependent LAN tests**
because no test adapter was selected. The focused chat/media suites pass 36,
message/lifecycle/incoming suites pass 18, and guide/home/layout suites pass 17;
these are subsets, not additional totals. The native observer helper compiles
and verifies against API 35. Python suites pass: observer 31, lifecycle 52,
incoming media 31, purchase capture 22, multi-device tooling 42 and isolated SDK
preparation 18. The multi-device suite includes the ten SDK Setup preparation
contracts and an actual FFmpeg composition check.

The guide footer now remains reachable while its body scrolls, including 200%
text and short landscape. Local playback shows the real media title, and tablet
copy says this device. The next five-layout run also captures the media chooser
and unobstructed Settings; the previous 14-image sets did not establish these
two screens' visual acceptance. These local checks do not replace that native
rendered evidence or physical LAN, billing and Cast validation.

## Archived September 25 verification details through the 3a0307f cohort

The following checkpoint text is historical. New native results and remaining gates are in [STATUS.md](STATUS.md).

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

## Archived September 25 verification through the fdebec3 cohort

Archived from STATUS on September 25 after the fresh 0454176 profile recovery
pass. These are historical results and investigations, not the current verdict.

Hosted Check `36043940260` at `1052a01` passes **780 app, 87 Nearby and 14
platform tests**, formatting, analysis, media contracts and the secret audit.
Same-source history restoration previously exposed a stale ready snapshot:
standard-layout Together `36037410096` tapped a disabled Play before the new
source finished loading. No native Play was sent. The app now shows an explicit
restoring state and disables old controls until restoration completes; the
driver waits for enabled controls and still taps only once. Fresh standard-layout
Together `36041063625` passes all 26 host and 25 guest stages with compact
recording, not altered UI size. Settled native positions match at 8,335, 53,361
and 55,987 ms. Original-frame review `36043849885` strictly decodes the sources;
all 144 exported PNG hashes match. Selected images show the real history
reconnection and restored player at 1:05. Recording gaps remain in its manifest.

The `6e46041` native cohort passes normal API 29/35 debug and API 35 release
install, native playback, Nearby, five viewport journeys, the runtime matrix,
normal release lifecycle, foreground audio focus, phone/tablet fullscreen,
RevenueCat Test Store purchase and same-customer relaunch/expiry. Lifecycle
`36037410201` changes process 3165 to 6071, restores 45 seconds without autoplay
and advances only after explicit Play. Local-file `36037410039` was blocked by
an emulator Google SDK Setup ANR over DocumentsUI; the strictly identified
emulator-only recovery at `56fcd32` passes 22 lightweight contracts and fresh
SAF relaunch `36039255967`, including the retained grant and 8-second position.

Network `36037410071` remains **failed in both attempts** at initial playback,
before the radio interruption begins. Attempt 1 times out reading the guest's
native position after 5.359 seconds. Attempt 2 completes native reads but still
has 19,845 / 22,342 ms positions after 30.128 seconds. Both clients remain
connected without peer errors. Syncplay 1.7.5 normally selects the slowest
watcher's position and `setBy` on ordinary heartbeats; the delayed guest causes
the host to rewind, then one-sided rate correction does not converge in time.
The guest sends no seek or user-change flag in that failed interval. Same-SHA
profile comparison `36041671936` passes initial convergence in 7.565 seconds,
then radio loss, no-autoplay recovery and explicit replay in 3.974 seconds at
49,173 / 49,196 native ms. It uses one API 35 AVD with two real STARTTLS clients
and two decoders; only the host is rendered. Peer and teardown errors are empty.
This passing profile run does not cancel the debug failures.

The new two-socket protocol regression models the service's automatic slowest-
watcher anchor and reproduces missing local catch-up after a buffered rewind.
Hosted Check `36042999733` at `4fc0caf` fails exactly that named assertion;
the other 779 app tests pass. The narrow `b689602` production fix watches the
native rewind's recovery using the existing 12-second/two-correction bounds,
without sending another room command. Independent source review finds no
blocking issue. Hosted Check `36043940260` at `1052a01` passes all 780 app tests,
including that previously failing regression. Fresh native debug/profile gates
are the next acceptance step for this production change.
No threshold relaxation or repeated Play tap is accepted as a fix.

The tablet stage fix at `6e46041` fits the available viewport and keyboard
inset. Reactions retain their spoken label and fit at large text sizes.
`9a3fc05` also corrects the reaction-echo test race and an unrelated offscreen
title expectation from Check `36037410520`. Recording-display Together
`36037966143` passes all 26 host and 25 guest stages. Hosted review `36040303581`
strictly decodes its originals; all 114 extracted PNG hashes match. Selected
original frames show complete video, chat and heart within the tablet stage.
This is sampled visual evidence, not full-motion or physical-device acceptance.

Fresh purchase `36037410075` passes 12 Test Store stages with fullyLive rendering
during SDK waits. Review `36039033397` verifies 47 original PNG hashes. Selected
frames show the native Test Store dialog, Plus activation, Restore feedback and
appearances. Native recordings still average roughly 6–9 pictures per second;
the 30 fps editorial export must preserve held frames and recording gaps.
Fresh lifecycle/fullscreen reviews `36039504553` and `36039152529` verify 34
and 42 PNG hashes respectively. These new sources are being edited into a
replacement film; the candidate below remains retained and unaccepted.

RevenueCat relaunch `36037410042` verifies the same customer's Plus state after
a process restart. Its sixth expiry poll observes the active entitlement become
inactive, refreshes the SDK cache and confirms Restore stays inactive. This is
fresh SDK/receipt evidence, not continuous film of the wait, identity recovery
after reinstall or Google Play production billing. Fresh SAF selection needs
no launcher/setup recovery; the blocked earlier run and narrow recovery
contracts are retained separately.

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

## Archived September 25 recovery investigations through 5ea2aa2

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
regressions pass in hosted Check `36062757882` at `68d9b51`: all 785 app,
87 Nearby and 14 platform tests, formatting, analysis, media contracts and
the secret scan pass. Debug network `36062762988` no longer blocks the Play
tap and requires no SDK Setup recovery. Initial playback converges in 4.356
seconds; automatic pause and no-autoplay reconnect pass. The complete run
fails when the guest decoder's HTTP connection to the fixture fails during
the outage (21:48:00.235 UTC) and leaves the source failed after TLS reconnect.
The host advances on explicit Play; the guest remains at 22,548 ms. All 456
native position records are indexed without rejection/drop; peer and teardown
errors are empty. This is a separate source-recovery defect, not an accepted
network pass. The follow-up now permits one paused reopening of the same failed
network source within 30 seconds of a real TLS reconnection. It preserves the
last reliable media clock, leaves healthy/local-file/receiver sources alone,
invalidates former source commands and never replays a pre-outage Play. Fresh
paused heartbeats (including those needing no FOLLOW action) distinguish a new
peer Play received during rebuilding; that Play still passes authorization.
Failed reopening retains the normal visible choose-video fallback without an
automatic retry loop. Fifteen bridge regressions and three native-platform
regressions pass in Check `36065517424` at `10f10ef` (803 app, 87 Nearby,
14 platform tests, analysis, media contracts and secret scan). Independent review
found that a second outage during rebuilding needed a fresh attempt after the
in-flight load failed. That boundary is now fixed with a sixteenth regression;
Check `36066044671` caught an additional old-Play regression when that in-flight
load succeeds: resetting the attempt budget must not reset the fresh-pause
requirement. The guard now remains independent of the attempt budget, including
healthy network sources after rejoin. All 16 bridge cases remain required;
Check `36066493312` stops in analysis because the new healthy-source assertion
was placed outside its scenario loop. Its placement is corrected; no app code
changed for that correction. A separate two-socket-client regression now covers
a settled non-buffering native interruption pausing Together, suppressing a
native auto-resume, and accepting explicit Play again. Check `36066905521` at
`4acc75e` passes all 805 app, 87 Nearby and 14 platform tests, analysis, media
contracts and the secret scan. That socket regression does not prove Android
focus delivery.
Source review additionally applies the stale-Play guard to accepted local files
and external targets, with two added no-rebuild regressions. Only a failed network
source on a capable local decoder can reopen; the broader guard only protects
play intent. Those two cases await the next hosted check. The native gate
now requires ready sources and original failed/loading/ready controller evidence
for any replacement; healthy controller identity, room and quota stay strict.
The lightweight network/setup contract suite passes 63 tests with one platform
skip; no local Flutter build, analysis, test suite or emulator ran.
Native debug `36066047985` at `f60c77a` stops at `initial-ready`, before either
radio is disabled: the independent observer cannot produce an active-window
hierarchy (`root_missing`). Sixteen native position records are retained with
no rejected/dropped samples; no SDK Setup recovery was used. This does not test
the source-reopening change and is not a network acceptance pass. Original
observer and window evidence is retained for diagnosis.
Repeated identical notices share the original expiry instead of extending it,
so repeated errors cannot permanently hide controls; a later occurrence after
dismissal starts a fresh notice. The Local audio-focus runner now retains its
permanent-loss case and appends independent transient loss/automatic-resume
acceptance with fresh nonce/UID/PID and current AudioService proof. All 29
lightweight Python contracts pass. A 180-second version of the same source
provides room for both cases without changing pause/recovery deadlines. Native
execution is still required; this does not establish Together-room focus behavior.
The initial transient run `36063115313` was intentionally cancelled after source
review found the inherited 90-second expected-duration default. `f56c8e8` aligns
that assertion with the 180-second fixture and passes the same 29 lightweight
contracts; normal-release run `36063562267` passes on the dedicated API 35 AVD.
The original 19 focused-window records and 16 UI XML files contain only the
foreground MainApp; four critical original PNGs are visually reviewed. Permanent
loss pauses within a 1,035 ms measured upper bound, holds 0:44 after release,
and advances after explicit Play. Transient loss pauses within 1,161 ms, holds
1:19, then automatically resumes within a 4,058 ms measured upper bound and
advances ten displayed seconds without a Play tap. These bounds include UI
observation time. AudioService proves the helper's GAIN/GAIN_TRANSIENT and the
app's focus regain with one unchanged foreground PID (2770), no Activity
pause/stop, no observation timeout or SDK Setup recovery. Both helpers are
removed. All three original recording hashes match; their cloud-decoded
47.437/51.449/42.673-second streams extend beyond the required observation with
new post-roll pictures. No local video decoding was performed. This proves
Local mode on one emulator, not physical hardware or Together-room interruptions.
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

## Archived September 25 interruption investigations through 60543ff

This is the historical investigation record moved from STATUS at `60543ff`.
Statements about pending checks describe that earlier checkpoint; use STATUS
for the latest accepted evidence and outstanding work.

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
  contracts and subsequent native run `36078684061` pass. That later result does
  not identify the cause of this older failure. Two SDK Setup ANR dismissals in
  preparation also prevent clean-install acceptance for the older run.
- Fullscreen `36074182951` passes the normal-release phone job. Three original
  PNGs show hidden controls, restored portrait playback and Home history; all
  three recording hashes match cloud-decoded originals. Motion/transition review
  remains open. The tablet job times out delivering an observer result before
  entering fullscreen; its failure PNG shows an unobscured playing app.
  Reconstructing all 12 progress messages exactly matches the retained stdout
  hash: no final result was delivered. Android's original system log records
  2.694 seconds of lock contention while unregistering UiAutomation, exceeding
  the two-second result budget. This supports an observer infrastructure failure;
  the capture remains failed, and neither its deadline nor acceptance is relaxed.

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

## Archived September 25 native focus and recording investigations through 37adcf6

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
compilation passes in hosted Check `36085892139` at `e94015e`. A fresh native
run remains required.

Failed-decoder `36086036490` at `4be67e8` now passes both offline checkpoints:
the cached public address is unreachable, the original guest decoder reports
a real Source error at 85,000 ms, and the byte proof shows every served span
below the unserved seek keyframe before the owned cap release. After reconnect,
the host retains controller 1 and the guest rebuilds controller 2 as 3, paused.
The strict continuity gate fails because the new decoder's first ready event
reports 0 ms while its initial 85-second seek is pending. Later room state is
paused at 37.133 seconds. The offline original PNG and all 88 accepted native
position records are reviewed; there is no SDK Setup repair. The target now
keeps loading through the restore seek and only then publishes ready, with a
regression that injects native buffering events during that pending seek.
Fresh failed-decoder acceptance remains required.

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

The bridge repair explicitly clears the native play request after accepting a
ready, non-buffering pause. Its queued correction is tied to the current source
and intent, so a newer Play or source load supersedes it; external receivers
are excluded. Socket regressions model a retained play request and require zero
native Play events on focus release. Independent review identifies a remaining
early-interruption gap: if focus returns before a peer command's settle window
ends, the pause can still be dismissed as an echo. That requires a reliable
native interruption policy rather than guessing from playback snapshots. The
held-interruption fix passes hosted Check `36086014156` at `4be67e8` with
831 app tests. Together focus is not yet accepted.

The short-interruption repair uses a pinned BSD-licensed copy of
`video_player_android` 2.12.2. A per-player policy pauses ExoPlayer synchronously
on transient audio-focus suppression, before focus can return. ExoPlayer keeps
ownership of audio focus; Local Mode retains its default behavior. The phone
target confirms the room's policy before exposing a new decoder or issuing
Play. Identity-scoped room ownership prevents old teardown from disabling a
replacement room's policy. New target tests cover reload, return to Local Mode,
overlapping ownership, pending policy updates, failure and Play cancellation.
The second independent review finds no remaining source defect. Hosted checks
now include the pinned player's native unit suite and a normal debug APK build;
this repair still requires fresh cloud and Android runtime evidence.

Initial policy Check `36087060781` at `ebc8f9c` accepts the pinned path lockfile
but finds two missing explicit capability casts and the frontend controller's
test-annotated player-ID accessor during analysis. The casts are corrected;
the ID use is isolated and documented at the Android adapter boundary. The
native extension and frontend versions are pinned and must pass the native
integration gates. These compiler findings are not runtime acceptance.

Check `36087429374` at `e639ef2` passes formatting, analysis and the normal
Android APK build. Its native unit suite stops before policy methods run:
the default SDK 36 Robolectric sandbox requires Java 21, but the runner used
Java 17. The native-test step now selects the runner's installed Java 21 and
retains SDK 36 coverage. The app suite reaches 819 passing tests before the
first fullscreen widget fixture times out: the native policy queue is created
in the fake zone, but its operations are awaited through the real async zone.
Flushing the constructor microtask alone is insufficient because Dart also
schedules later listeners in the originating Future's zone. The fixture now
creates its native target in the same real zone as those operations, retaining
fake-clock ownership for app/UI timers. Both test repairs require a fresh
hosted Check; neither failed job is accepted.

Check `36089125495` at `433d365` now passes all jobs: 837 app tests, 100 native
player tests without skips, normal Android debug APK, formatting, analysis,
Nearby/platform contracts, independent observer compilation and media/secret
checks. The native suite uses Java 21 with SDK 36 by default. Fullscreen fixture
queues are created in the real async zone and UI tests await completed Play
before evaluating control hiding. The preceding run `36088550167` passed its
100 native player tests, but its stalled app job was superseded; it is not a
passing full Check.

Fresh normal-release Local Mode focus `36089506421` at `433d365` passes with
the pinned player on API 35, app PID 2872. Permanent focus loss pauses within
an 845 ms observed upper bound, holds at 44 seconds after release, and explicit
Play advances 16 seconds. Transient loss pauses within 1,729 ms, returns to
playing within 4,821 ms of release, and automatically advances 11 seconds.
Three original phone PNGs and all three recording hashes are reviewed; cloud
decoding succeeds. Preparation closes one Google SDK Setup ANR before the focus
requests, so this is not zero-repair cold-start acceptance. Recording gaps and
unreviewed full motion remain disclosed. Together focus and physical-device
behavior are separate outstanding gates.

Failed-decoder run `36088578047` at `4cc57b9` reaches initial native convergence
in 3,729 ms, then times out in the Flutter screenshot helper before any radio
interruption. The original initial PNG and failure trace are retained. This
does not exercise the restored-position fix. The network journey now uses its
existing external Android screencaps and foreground-checked accessibility
snapshots at all four playback checkpoints, without converting the Flutter
video surface for duplicate captures. Every capture must complete before its
exact acknowledgement; missing or reordered capture phases fail validation.

Together-focus run `36088605515` fails before its first focus request: the raw
focused window is a Pixel Launcher ANR over MainActivity. The original failure
PNG has been inspected. Its runner now reuses the dedicated-AVD pre-install
setup check, requires a fresh unchanged Home observation and retains native
ANR/lifecycle diagnostics if a later stage fails. Any post-install foreign
window still fails; no interruption assertion or timing bound is relaxed.
Both native journeys require fresh runtime evidence.

Together focus `36090450938` at `1ab03e7` passes the new pre-install Home
check with no ANR, then exposes the short-interruption defect in app PID 3857.
The real helper holds transient focus for 356 ms and releases it 1,759 ms after
the pre-Play marker, inside the unchanged three-second window. Android logs
both loss and gain, but the continuous monitor sees neither a native nor a
room pause; the original post-release PNG still shows Pause. MainActivity
remains foreground. The suppression-listener policy is therefore insufficient
despite its passing mocked native tests. Media3 1.9.2 can withhold listener state
updates while native commands are pending; the repair must receive focus
commands directly, with one focus owner and separate Local/Together resume
policies. Fresh native proof is still required.

The replacement now gives each player one Media3 AudioFocusManager on its
application thread and disables ExoPlayer's automatic focus owner. Direct loss
callbacks pause and report false to Dart even if buffering already made native
isPlaying false. Together cancels pending resume; Local Mode can resume on gain,
unless explicitly paused or the decoder stops. End/error and disposal release
focus. The deferred renderer reset checks for intervening pause or interruption
before restoring playback. Source tests cover direct callbacks without any
suppression-listener event, denied focus, ducking, mixing, per-player isolation
and delayed reset. Source review and whitespace checks pass; compilation,
native unit results and both Local/Together runtime gates remain outstanding.

Failed-decoder `36090309937` at `1ab03e7` now gets through real radio loss,
socket unreachability and the original native decoder failure. It stops at
`offline-confirmed` because the second recording's frame-clock comparison
rejects a 104-microsecond difference. All 233 encoded sample timestamps match
Android 15's muxer duration adjustment when derived from the raw Winscope
timestamps; the existing 100-microsecond comparison does not model that
adjustment. This original run remains failed, and never validates the
reconnected decoder. The recording contract needs the platform's actual
timestamp mapping, without weakening frame count, coverage, hash or decode
requirements.

The recording mapping is now corrected using Android 15's actual 90 kHz
quantization and sub-100-microsecond duration reuse, with only a 0.51-microsecond
allowance for ffprobe's decimal output. Four focused metadata contracts pass,
including rejection of negative raw duration before adjustment. Independent
metadata reads reproduce all 158 and 233 original encoded timestamps without
decoding media locally. The original failed run is unchanged; fresh native
failed-decoder recovery still must pass.

Normal-network `36091067116` at `1ab03e7` stops before radio loss at its
initial native UI capture. MainActivity remains focused with the same PID 3155
and the original PNG shows both participants and playing video, but the
independent observer cannot retrieve an active app root in 15 bounded attempts.
Its early diagnostic contains only a non-active system window; no app ANR or
fatal exception is found in the retained log. The screenshot does not replace
the required complete accessibility capture. This run is failed, and the
precise observer/platform cause is not established.

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
