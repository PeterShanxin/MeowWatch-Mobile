# Delivery status

Last updated: 2026-09-26 (Asia/Shanghai). **Submitted to RevenueCat Shipaton 2026 for Next Gen review, with the hardware and runtime limits below disclosed.**

The owner authorized final submission. Devpost confirms submission `1196850`
at **2026-09-25 16:17:48 UTC** (September 26, 00:17:48 in China/Singapore).
Both the live project API and authenticated form verify **Submitted, 5/5 steps**.
Public entry: [MeowWatch Mobile](https://devpost.com/software/meowwatch-mobile).

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
Nearby discovery, pairing, controls, saved reconnect and revocation now pass
on the September 25 phone check. The owner requested virtual/client testing
instead of further physical-phone testing; the phone remains released with
its settings restored. The local Windows ARM host is not supported by Google's
Android Emulator. The owner accepted an ordinary local Windows client on the
secondary monitor plus one cloud Android emulator. That ordinary cross-client
check passes in run 36143500404, with the identical downloaded-media fallback
and limits documented in [cross-client acceptance](CROSS_CLIENT_ACCEPTANCE_2026-09-25.md).
It is not a second physical Android check.
Native Nearby chat/reaction/typing relay and desktop-process-restart persistence
have not been accepted on the paired Android/Windows devices. Social relay has
unit and transport coverage; ordinary Together social behavior has independent
client evidence. The public Windows/cloud room test is not a private LAN
companion test. The phone is released at the owner's request, and a cloud
emulator cannot join this trusted LAN without a new network arrangement.
No Cast receiver is available. Receiver behavior remains unverified, with phone
playback as the fallback.
Additional emulator runs cannot establish hardware behavior.

The owner confirmed that Nearby should remain a secondary, explicitly paired
desktop remote. Do not add automatic nearby room creation or a large Nearby
chapter to the film. Prioritize distant Together sessions, recovery, phone/tablet
usability and a clear, reliable Plus flow. The owner also requested a more
designed hybrid film: accurate React UI animation for explanatory shots and
real-device footage for runtime demonstration, clearly distinguished. Following
review of the hybrid edition, the owner requested a continuous-shot visual
treatment and one consistent palette. The film uses a deep navy stage, quick
0.3–0.5-second device/camera moves and still reading holds. Titles leave by
moving offscreen; small translucent touch indicators mark taps. Its edited
sources remain labeled.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Verified on emulators | Current product source `0df32c6`, packaged from `a65b8ef`: normal install 36125719065 passes API 29/35 debug and API 35 release. The ordinary Test Store debug APK is the judging build. Clean launch alone does not establish the complete repair-free demo rehearsal |
| 2 | Public, licensed, documented, secret-free repository | Verified | PR #1 is merged as `7f05b9f`; main contains the complete app, AGPL license, setup, provenance and submission assets. Check 36156902449 passes at final PR head `a20921f`. Its secret audit covers 645 tracked files and 274 fetched commits with zero snapshot/history findings. Public prerelease `v0.1.0` includes the ordinary APK and source/install receipts |
| 3 | Clear first-launch create/join | Verified on emulators | Ordinary-APK 36137630270 passes the first-run guide, visible Start and invitation code, and Join on independent API 35 phone/tablet emulators. Five-viewport run 36103033060 and Together 36103033024 attempt 2 also pass |
| 4 | Two real clients repeatedly play/pause/seek in sync | Verified on two emulators and Windows/cloud Android | Ordinary-APK 36137630270 passes advancing native playback and play/pause/seek in both directions on independent phone/tablet emulators. [Cross-client 36143500404](CROSS_CLIENT_ACCEPTANCE_2026-09-25.md) also passes ordinary Windows/cloud Android controls in both directions, including matching paused 3:54 and 4:58 positions; Windows uses an unchanged downloaded copy after remote-source failure. Failed-decoder recovery passes 36101860905 on identical product code. Physical two-Android behavior and frame identity are not claimed |
| 5 | Real-session chat/reactions/presence | Verified on two emulators | Ordinary-APK 36137630270 visibly passes presence, chat in both directions and a peer reaction on the independent phone/tablet emulators. Earlier Together and Test Store journeys also pass; 36103033131 verifies a premium reaction received by a headless TLS peer |
| 6 | Disconnect/reconnect/lifecycle recovery | Verified within stated runtime limits | Failed-decoder profile 36101860905 and current-head normal network 36131237104 pass. The latter uses one API 35 AVD, two real STARTTLS clients/decoders and one rendered MainApp. It verifies actual emulator radio loss, paused same-room recovery, unchanged quota and explicit replay/seek. Hosted lifecycle and physical Local/Nearby restart also pass; physical Together radio-loss recovery is not claimed |
| 7 | Local Mode and Continue Watching | Verified on physical phone and emulators | Ordinary APK `67d0206` plays Sintel on physical OnePlus Android 16 and restores 19 seconds paused after process restart. Hosted lifecycle preserves 69 seconds; SAF and independent-device history checks also pass |
| 8 | Secure phone-to-desktop discovery/pair/control | Physical core path verified; companion social acceptance remains limited | Ordinary Android `67d0206` and Windows `3ebba3a`: discovery, approved pairing, Play/Pause/±10-second seek, saved reconnect after phone relaunch, desktop revocation and rejected credential reuse pass. The stale device-selector label fix passes hosted Check 36124174769. Native companion social relay and desktop process restart are not claimed; phone playback and direct Together chat remain the verified fallback |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Verified in Test Store with stated runtime limits | Current-head hosted 36131237099 passes 12 stages including one free and two Plus hosts and clean-cache Restore. Its original Settings screenshot was visually inspected: active Plus and successful Restore feedback appear directly below Restore. Physical OnePlus passes native cancellation/failure/success, confirms active-customer Restore feedback, and retains Plus after relaunch. No Google Play production billing claim |
| 10 | Correct daily quota and session continuity | Verified in native flows and tests | Ordinary-APK 36137630270 completes one free host, free guest join, quota paywall on the next Start, native Test Store purchase and a distinct Plus host. Earlier Together and purchase journeys verify unchanged quota after link/media recovery/history and two distinct Plus hosts. Midnight has unit coverage; native journeys do not cross midnight |
| 11 | Rendered phone, small phone, tablet and rotation QA | Verified within physical and emulator scope | Ordinary-APK 36137630270 passes independent phone/tablet layouts and the phone's first fullscreen entry, Android tip and Back. Five-viewport and normal-release phone/tablet fullscreen gates pass. Physical OnePlus portrait/landscape playback, hidden bars/controls and Back are inspected and recorded; hybrid film review is separate |
| 12 | Reliable Cast or exact blocker and fallback | Hardware blocker documented | Android sender and same-room handoff are implemented. The owner confirmed no Google Cast receiver is available on September 25. Physical receiver discovery/playback/reconnect are unverified; the physically exercised phone playback path is the fallback. No receiver success is claimed |
| 13 | No placeholders, dead ends or silent failures | Verified for the rehearsed demo path | Ordinary-APK 36137630270 completes the visible first-install path through two-client Together playback, history, quota paywall, native purchase, Restore and Local resume without a dead end. Earlier onboarding, recovery and failure-path checks retain their separate scope; physical acceptance and its corrected UI defects are recorded below |
| 14 | Clean-install full demo rehearsal | Verified on two API 35 emulators | Ordinary `lib/main.dart` debug/Test Store APK run [36137630270](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36137630270) at `b5b9f77` completes on fresh independent phone/tablet emulators. It passes onboarding, visible invitation-code join, the same controlled URL and advancing native playback, two-way controls/chat, reaction, fullscreen/Back, both histories, free-host quota paywall, native Test Store success, a distinct Plus host, Settings Restore and Local leave/resume. This is emulator evidence, not physical two-device or production Google Play billing proof |
| 15 | Shipaton submission confidence | Submitted and verified | Mobile PR #1 and desktop PR #279 are merged. Android `v0.1.0` and signed Windows `v0.51.0-alpha` are public. Complete ordinary-APK and Windows/cloud rehearsals pass. The 94-second film is Unlisted with HD processing complete and saved in the actual competition form. Devpost's public page includes the video, APK link, artwork, new mobile work/provenance and validation limits. The academic account email is verified. After owner authorization, Devpost confirms submission `1196850` and the form shows Submitted, 5/5 steps |

## Current verification

### Final repository checks

The Android [v0.1.0 Test Store prerelease](https://github.com/PeterShanxin/MeowWatch-Mobile/releases/tag/v0.1.0)
is public at `a20921f`. An unauthenticated request to its APK download returns
HTTP 200 and the expected 187,653,399-byte size; GitHub's uploaded digest matches
the retained build receipt. The APK, source/install receipts and AGPL license
are attached. Application code, packaged assets and dependencies remain
identical to `a65b8ef`. Devpost's public project page now embeds the final film,
links this download and both source repositories/releases, and discloses the
Nearby social-relay and Cast limits. The actual competition judge notes save
the same release and video URLs. Final submission is verified above.

Final PR head `a20921f` includes only the lifecycle test correction and delivery
documentation after `31c28a4`. [Check 36156902449](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36156902449)
passes analysis/app tests, Nearby package contracts, media contracts, observer
compilation and native player checks. The fresh secret
audit scans 645 tracked files and 274 fetched commits with zero snapshot or
history findings and no suspicious paths. Final-head lifecycle `36156901899`
also passes. All 25 product/check jobs at that final PR head pass, with two
conditional jobs skipped. This includes final ordinary installs, fullscreen,
network recovery, five viewports, phone/tablet Together, focus interruptions,
purchase, same-customer relaunch and actual expiry. PR #1 is merged as `7f05b9f`
with the same application tree. The tag-triggered diagnostic contracts also
pass, with their extraction job skipped; these are separate from product
acceptance. The tag- and merge-triggered diagnostic motion probes `36157335828`
and `36158367765` were stopped under the recording-tool freeze; they are not
product acceptance gates.

Post-merge normal install, playback, Nearby, SAF and lifecycle workflows also
pass at `7f05b9f`. The merge's initial Check run was superseded by documentation
commit `b604a6d`; [Check 36158591927](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36158591927)
passes in full. Later delivery-record updates change documentation only and
reuse those checks; application and test source are unchanged.

At PR head `31c28a4`, 24 checks pass and two conditional jobs skip. The Check
workflow's tested merge tree is identical to that head. Its secret audit scans
645 tracked files and 272 fetched commits, with zero snapshot/history findings
and no suspicious tracked paths. The SAF job's first attempt failed on a Gradle
download HTTP 500; the network job failed while unpacking the emulator image.
Both pass unchanged second attempts. Tablet fullscreen also passes its second
attempt after a corrupt native recording stopped the first attempt.

Lifecycle `36151161242` fails twice at the visible HOME pause tolerance, with
actual paused playback after foreground return. Attempt 2 observes 40 seconds
in a native tree starting at device time 120.416, then sends HOME after a
121.59 clock reading and returns paused at 45 seconds. Test-only `20785d1`
accounts for that measured foreground sample age while retaining the four
displayed-second tolerance, eight-second HOME hold, same process, paused
stability and explicit replay checks. Invalid or over-four-second sample ages
fail. All 140 focused host checks pass and an independent source review finds
no blocking defect. Fresh native validation [36155029033](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36155029033)
passes on API 35 using the normal release entrypoint: HOME holds 8.58 seconds,
the displayed position changes from 36 to 39 seconds and remains paused after
return, and explicit replay advances 11 seconds. A new process restores the
saved 56 seconds paused, then explicit Play advances another 10 seconds.
The measured pre-HOME sample age is 0.668 seconds. This is a visible
timeline tolerance with whole-second labels and a capture interval, not proof
of an exact four-second real-time pause latency. App and packaged asset source
remain unchanged from the published-build candidate `a65b8ef`.

At `8720496`, [Check 36146573344](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36146573344)
passes formatting, analysis, tests, native player, normal debug APK, package,
media and secret gates. The runtime checks retain three initial failures:

- Tablet fullscreen `36146572960`: before entering fullscreen, a 1.437-second
  UI traversal crossed a timeline tick and read both 0:43 and 0:44. The strict
  parser rejected the sample. Original screenshots show advancing playback;
  that attempt does not establish fullscreen acceptance.
- Together focus `36146573123`: the native UI showed paused playback, but its
  first observable capture began 4.311 seconds after the focus request and
  finished at 4.480 seconds. It cannot establish the four-second pause bound
  or prove that the app missed it. Both jobs pass their second attempts without
  a code change. The focus report passes early-short, permanent and transient
  interruption, retained pause and explicit replay; the tablet report has
  `completed: true` with no error. Original failed attempts remain retained.
- Test Store expiry `36146572929`: purchase, same-customer relaunch and Restore
  pass, but expiration validation compares clocks from different sources.
  RevenueCat reports inactive at 14:37:32.453 UTC, after its 14:37:32.000
  expiration, while device time is 14:37:31.967. The final inactive-Restore
  check was not reached. Test-only fix `6e7b03e` compares expiration with the
  SDK's request time and retains inactive entitlement, customer continuity
  and Restore assertions. Its regression fails before the fix; all 58 billing
  host tests pass afterward. Fresh native acceptance `36149213163` passes
  purchase, the same customer after process restart, actual expiration and
  Restore remaining inactive.

Application code is unchanged from `0df32c6`; none of these test changes alters
purchase, playback or quota behavior. Mobile PR #1 is now merged; the original
failed runs remain part of the evidence record.

### Physical acceptance and final presentation revision

[Physical acceptance](PHYSICAL_ACCEPTANCE_2026-09-25.md) records the actual
OnePlus Android 16 / Windows runtime and its limits. It also verifies native
RevenueCat Test Store cancellation, failure, success, active-customer Restore
success feedback and Plus after phone process restart. Clean-cache restore and two
Plus hosting sessions retain the separate hosted evidence below. The physical
fullscreen capture shows advancing video with hidden controls and system bars.

`0df32c6` is the latest product source: it includes the Nearby sheet's live
connection-status fix and Restore feedback directly below the purchase action.
[Check 36124174769](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36124174769)
passes all required app, native player, Nearby, media and secret checks,
including both new UI regressions. Earlier formatting, mounted-context lint and
exact film-asset path-classification failures are corrected; no secret scan was
disabled. Later commits change only the film, documentation and rehearsal code.

At PR head `9e3f033`, [Check 36131237368](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36131237368)
passes. [Normal network 36131237104](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36131237104)
also passes actual emulator radio loss and paused same-room recovery, unchanged
quota, explicit Play/Pause/Seek and peer synchronization. Its runtime is one
API 35 AVD with two real STARTTLS clients and Android decoders; only MainApp's
host player is rendered. This is separate from the accepted forced-failed-decoder
profile and from the ordinary-APK two-device rehearsal.

Local audio-focus run `36131237463` attempt 1 stops before sending any focus
interruption: advancing playback is visible, but the first native recording
contains corrupt H.264 frames. It establishes no new focus-recovery result.
The single same-head retry, attempt 2, passes on an ordinary `lib/main.dart`
APK in an API 35 emulator. The foreground focus probe pauses Local playback
within the observed 956 ms upper bound; the permanent-loss path stays at
41 seconds after release until explicit Play, then advances to 56 seconds.
Transient loss pauses at 78 seconds and Local playback resumes on focus return,
advancing from 84 to 95 seconds. The app process stays the same, and the probe
and observer are removed. These are emulator results, not phone-call hardware
evidence. No recording verifier was relaxed.

Earlier rehearsal `36120725219` loaded the exact fixture URL on both devices,
then failed because its observer required a filename absent from the landscape
layout. The correction requires the preceding exact-URL submission and the
actual 90-second native timeline; it does not lower playback/synchronization
acceptance. Earlier input/keyboard/invitation observer failures remain failed.

[Remotion render 36130037521](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36130037521)
exports source `ebc58c4` as 1920 × 1080 H.264/AAC, 30 fps, 94.059 seconds.
It combines labeled React UI animation with actual phone Local/fullscreen and
emulator purchase footage. The navy stage remains consistent; camera moves
settle within 0.3–0.5 seconds, titles move offscreen, and small translucent dots
mark taps. TypeScript checks and representative Studio/cloud still review pass.
The downloaded export played to its 94.059-second ending at 1× in the browser
without a media error; representative frames were visually inspected.
This export replaces the earlier slow-moving editions. The final
[YouTube video](https://youtu.be/gRUYlHb3LiI) is saved as **Unlisted**;
SD and HD processing are complete, and the upload copyright check reports no
issues. That automated check is not a legal determination. On September 25
the owner requested the final video update and submission link. Studio confirms
the Unlisted change is saved. The project connector and actual competition form
contain the final URL. The form initially showed 4/5 steps after saving the
video; final submission now shows 5/5. The earlier silent private upload is
superseded.

The owner requested the phone back. At 10:36 UTC its original 30-second timeout
and charging-awake setting were restored and read back; developer mode and USB
debugging were confirmed off. Wireless debugging shutdown closed the transport
before readback, after which the device/forward lists were empty and the
task-owned ADB server was stopped. The Windows companion exited and both
review firewall rules were verified absent. Latest UI-only fixes retain hosted
verification scope. Heavy builds, emulators and full rendering remain hosted.

Normal install `36123942946` passes API 29/35 debug; its release build fails on
external Maven HTTP 429. Current-source
[install 36125719065](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36125719065)
then passes API 29/35 debug and API 35 release at `a65b8ef`, with product code
unchanged from `0df32c6`.
Complete rehearsal `36122797821` reached advancing playback on both devices and
a guest-to-host pause, then confused the slider thumb bounds with the whole
track. The track-location fix retains the unchanged two-way seek requirements.
Later `36125073381` fails earlier: a spurious leading character makes the guest
join a different room. Its hierarchy shows the entry field was already focused;
the runner now avoids tapping that field again and requires exact visible input
before submitting. Run `36126715801` then passes both directions of native
play/pause/seek and visibly delivers the phone message to the tablet, but its
receipt check expects a standalone message label while Flutter merges sender
and body. The dedicated chat receipt check now accepts the exact complete body
in that merged label, excludes input fields and rejects partial matches.
Run `36128627853` then passes both chat directions and reaches the reaction
picker, where the runner chooses a nonclickable semantics label rather than
its visible clickable heart. The exact heart target is corrected. The same
run's home hierarchy also establishes the complete clickable Local Player Mode
label, which the later step now uses. Run `36130217458` then passes both control
directions, both chat directions and the peer reaction. The app enters fullscreen,
but Android's first-use "Viewing full screen / Got it" overlay blocks the app
hierarchy observation. The runner now reuses the existing strict system-tip
validator, confirms fresh button bounds and acknowledges the visible tip; the
original app fullscreen/Back checks remain. Sixteen Python checks pass.
Rehearsal `36132938666` at `238cc6e` passes the fullscreen tip and Back, then
fails to parse tablet history. Its original screenshot and hierarchy show the
correct room and saved `0:42 of 1:30`; Android merges that context into the
progress bar label. `33ea6e7` matches the complete context line inside that
label, retaining exact room/source and progress requirements. Seventeen focused
runner checks pass. Run `36134921762` at `bae4cdf` then passes both devices'
history and stops at the next Start action. Its landscape phone home shows the
hero and Continue Watching, with Start below the viewport; the runner swipes
toward the top. The direction is corrected, retaining a fresh exact clickable
target check after every swipe. Eighteen focused runner checks pass. Purchase,
Restore and Local Mode were not reached in that failed run. An identical queued
push run was cancelled to avoid duplicate work. These earlier failed runs remain
failed; the subsequent complete rehearsal is the accepted result.

[Ordinary-APK rehearsal 36137630270](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36137630270)
at `b5b9f77` completes the full visible journey with no integration-test
entrypoint. One debug APK (`ae42360ebf0b9522a78785a2c622dabb197551a6b36376cbd219d27b6f683e13`)
runs on independent API 35 x86_64 `sdk_gphone64_x86_64` phone and tablet
emulators (`emulator-5554`/`emulator-5556`), using the same controlled 90-second
fixture URL. Its result reports `completed: true`, 39 phone phases and 21 tablet
phases. The ordinary UI shows the native RevenueCat Test Store
`TEST VALID PURCHASE` dialog; the visible first and Plus-host invite codes
differ. Settings shows active Plus and the successful Restore message beside
its action. Local history saves `0:14 of 1:30`, and selecting that card restores
the native player paused at `0:14`. Original XML and screenshots for these
stages were inspected. This closes criterion 14 within emulator/Test Store
scope; Cast receiver and production Google Play billing remain unverified.

### Earlier accepted product baseline, September 25

The physical-test candidate is `67d0206`; its `lib`, `android` and `assets` are
unchanged from frozen product `5f5dd7f`. Later `d8b55b2`/`7bcd6f4` commits prepare
the film and documentation on `feat/submission-showcase`. They do not rebuild
or alter the app. This paragraph records the earlier candidate; PR #1 now
includes the later product fixes through `9e3f033` as recorded above.

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
a short moving Studio preview were inspected. This edition is superseded by
the accepted `36130037521` export above. The first normal-APK rehearsal
`36111219476` prepared both emulators but
stopped before app installation because its driver could not find `adb` in PATH.
`b46d79d` supplies the platform-tools path; rerun
[36112282849](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36112282849)
was an earlier attempt; the complete `36137630270` rehearsal above is now the
accepted ordinary-APK result.

[Film export 36106912082](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36106912082)
produces the earlier 94.000-second, 1920 × 1080 silent H.264 candidate. All 2,820
frames decode in hosted CI; representative output frames and the final free-host
card are inspected. Sources, separate runtime boundaries and the complete story
are in [DEMO_SCRIPT.md](DEMO_SCRIPT.md). The entrant authorized a private YouTube
upload, which is saved and verified as private. A bounded 360p browser replay
reached the end with sampled visual checks. The final Remotion export and
unlisted video above supersede this candidate.
No local emulator or encoding process was started.

The local delivery folder contains the normal Test Store APK, the film,
unsigned Windows companion ZIP, source/build receipts, artwork and rehearsal
instructions. Desktop packaging
[36103713800](https://github.com/PeterShanxin/MeowWatch/actions/runs/36103713800)
and Windows CI `36103713926` pass at `3ebba3a`. This is a build receipt, not
physical Nearby or current Windows UI acceptance.

Shipaton registration and explicit rules/terms acceptance are complete.
The [Devpost project](https://devpost.com/software/meowwatch-mobile) has project
copy, technology tags, repository links, cover, original
icon/screenshot, Android platform, RevenueCat project ID, authorized academic
email and judge notes. The browser initially showed 4/5 sections after saving
the final video link. Updating
the description through Devpost's project connector at 13:53 UTC published the
project page (version 3); the hackathon entry had no submission timestamp then.
Publication alone did not submit the competition entry. The
updated description includes physical Nearby/purchase acceptance and the complete
ordinary-APK rehearsal, while retaining Cast and production-billing limits.
The supplied academic
domain is covered by JetBrains/swot, including its documented subdomain rule;
the entrant confirms GitHub sign-in uses that school email. This is domain and
entrant evidence. A September 25 authenticated account read also confirms its
email exactly matches the entrant-authorized academic address; no address is
stored here. This is not a separate Devpost eligibility decision. After mobile
repository closeout and explicit owner authorization, the final Submit page
now confirms Submitted with the accepted rules/terms checkbox and 5/5 steps.

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
was merged on September 25 as `3b8b976` after the maintainer confirmed the final
two-instance check at `3ebba3a`. Application source is unchanged by the merge.
Tag `v0.51.0-alpha` passes [signed release 36147584974](https://github.com/PeterShanxin/MeowWatch/actions/runs/36147584974).
The GitHub release is published; R2 latest/changelog contain `0.51.0-alpha`,
and its 35,292,735-byte public ZIP is reachable. The downloaded GitHub ZIP
matches R2 SHA-256 `f0a61b5489e6344c3dfa67ccb7a17a1d3ff1e74c01a24050b3aed6fd34cbb4dc`
and its version-bound Ed25519 signature verifies against the app's public key.
The merged feature branch is removed; three untracked deferred harness files
are preserved in the companion worktree. Requested Copilot review returned an
account-quota failure and performed no review; it is neither an approval nor a
pending review.

The companion at `dba4b57` adopts the `bd931d5` dependency pin and passes 38 Nearby tests,
analysis and a normal Windows Release build. The first full local test process
ended with incomplete tests; a separate retained run completed **1,494 tests**
with exit zero. Its original log and exit receipt are retained. Hosted Windows
[Analyze & Test](https://github.com/PeterShanxin/MeowWatch/actions/runs/35988145930)
and Package Check also pass at `dba4b57`. The later physical and ordinary
cross-client checks, current-head hosted gates and maintainer confirmation above
close the native/manual gate for the final `3ebba3a` application source.

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
The final 94-second export has been replayed and the complete clean-install
rehearsal now passes as documented above. Historical runs and asset provenance are preserved in
[Acceptance history](ACCEPTANCE_HISTORY.md).

## Human/external dependencies

- The entrant confirmed active student status, local age of majority, access to an academic email, registration eligibility and explicit rules/terms acceptance. Registration is complete. The authenticated Devpost account email matches the authorized academic address. Project-specific ownership/new-work responsibility remains with the entrant; registration is not an organizer ruling.
- RevenueCat login/Test Store catalog setup and user acceptance of the Android SDK license are complete. RevenueCat email confirmation remains visible.
- Physical Android and trusted physical LAN are available and exercised as documented above. No physical Cast receiver has been established; phone playback remains the working fallback.
- The desktop maintainer confirmed final two-instance acceptance; PR #279 is merged, and signed release `v0.51.0-alpha` and R2 verification pass.

## Live development recording

At delivery closeout, the task-owned showcase, Remotion Studio and movie preview
services were stopped. No listener remained on their ports 18769, 3010 or 8766
(or the earlier ports 8765 and 18775). The last development manifest retains
337,675,462 bytes in 2,699 chunks and a gap state, last updated at September 25
12:38 UTC. Its old browser tab was no longer controllable; a final browser flush
could not be verified. The original manifest is preserved without relabeling it
complete. This development canvas is separate from the accepted 94-second film
and does not establish continuous recording through the end of development.

The following are historical recording checkpoints.

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
