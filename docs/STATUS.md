# Delivery status

Last updated: 2026-09-18 (Asia/Shanghai). **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Partial | Fresh 54b4203 API 35 debug, API 29 debug and API 35 release normal installs pass independent audit, including seven intake reviews and two confirmed playback cases per variant. The late SDK Setup ANR recovery branch is not exercised in this run. Physical acceptance remains separate |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public AGPL-3.0 repository. The 54b4203 working-tree snapshot passes Gitleaks 8.30.1 with zero findings in 502 tracked files and 68 all-ref commits; no suspicious tracked paths. Final artifacts and repository closeout remain open |
| 3 | Clear first-launch create/join | Partial | 2fc38317 passes all five first-use/layout drivers and teardown. The compact landscape guide's primary instructions and fixed footer are visible; supplemental notes scroll. 5137e58 production Together passes actual Start, invitation review and Join on independent emulators |
| 4 | Two real clients repeatedly play/pause/seek in sync | Partial | 6c44e415 runtime matrix passes on two API 35 emulators after fixing the stale pause snapshot. 5137e58 production Together also passes all named two-way playback checkpoints. Equal position checkpoints do not establish identical decoded frames or physical-device behavior |
| 5 | Real-session chat/reactions/presence | Partial | 5137e58 production Together passes chat, reactions, presence and confirmed peer-link playback on independent phone/tablet emulators. 2fc38317 purchase also proves the premium reaction received by a TLS peer. Final submission film remains open |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | 8720304 normal release lifecycle passes independent review: real HOME, paused foreground, explicit Play and new-process history restoration. 115454e audio-focus interruption also passes. Actual radio-outage acceptance remains open; repeated native-test setup failures are retained below |
| 7 | Local Mode and Continue Watching | Partial | 2fc38317 native playback, SAF relaunch, normal lifecycle/history resume and all five complete layout drivers pass. Each layout retains 20 verified app steps and 16 screenshots. Physical-device acceptance remains separate |
| 8 | Secure phone-to-desktop discovery/pair/control | Partial | 2fc38317 Android Nearby passes within its emulator boundary. Desktop f5a9103 clean Release builds and its actual Windows UI was inspected. Physical Android-to-Windows discovery/pair/control/revoke/restart proof remains open |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | 2fc38317 production purchase passes 12 stages, one free and two paid hosts, native cancel/failure/success and same-customer restore. The 6c44 runtime billing/hosting jobs also pass. Diagnostic run 35240675074 at 9e032ba passes same-customer process relaunch, accelerated renewals, final expiry and inactive Restore; the earlier 2fc contradictory result did not recur and its cause remains unproven. Physical and Play-production evidence remain separate |
| 10 | Correct daily quota and session continuity | Partial | 6c44e415 runtime hosting passes 14 checks, one free plus two distinct Plus sessions, reconnect and same-process service/disk reopen without recharging. 5137e58 production Together passes endpoint/ledger preservation and repeated-room/free-joining checks. Actual radio-outage continuity remains open |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | Official unpatched Flutter 3.44 at 2fc38317 passes all five layouts and teardown with 80 native PNGs and five intact videos. Compact guide and Settings/Appearance/paywall transitions were visually reviewed. Purchase footage also proves corrected busy text in Cozy and Glass Aurora. Physical gates remain open; SDK candidate is unadopted |
| 12 | Reliable Cast or exact blocker and fallback | Partial | Android sender and same-room handoff are implemented. Actual receiver acceptance awaits hardware; phone playback fallback is available |
| 13 | No placeholders, dead ends or silent failures | Partial | 2fc38317 verifies guide, loading text, modal transitions, clean install and lifecycle. Later targeted matrix, expiry and production Together runs pass; the prior Restore anomaly remains unexplained. 5137e58 native footage proves readable 404 recovery and normal loading text. Final interruption gates and review remain open |
| 14 | Clean-install full demo rehearsal | Partial | The 2fc cohort remains 8 passing and 3 failed workflows. Later targeted 6c runtime matrix, 9e expiry and 5137e58 production Together checks pass. Final complete rehearsal, interruption coverage and the under-two-minute submission cut remain open; paired recording still has visibly sparse motion |
| 15 | Shipaton submission confidence | Partial | Brand kit and original-size submission screenshot are prepared. Final under-two-minute film, full rehearsal, physical gates and remaining eligibility/legal checks remain open |

## Latest targeted native verification

Current local verification on official Flutter 3.44 passes formatting, analysis,
**725 app tests with zero skips**, and a normal debug APK build. Same-host Nearby
TLS tests use the actual Windows WSL virtual adapter; this is not physical LAN
acceptance. The short-landscape join regression now keeps both the editable text
and full error visible above the keyboard, with accessible and pointer-drag
dismissal retained. Fresh five-layout native run `35258088967` passes at
`af45d24`; independent original-image and keyboard review is in progress. Independent
review also reproduced stale fullscreen Retry callbacks overriding a later entry
or replacement room; revision/lifecycle guards and owned-notice cleanup fix that
case, including preserving unrelated queued app messages. All eighteen immersive
platform/widget tests pass; these are included in the app total.

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
Native read timing diagnostics are the next step; neither failure establishes
a production synchronization defect or justifies weakening a timeout.

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
real Linux HTTP/ownership tests and the focused review pass. Native performance
and film-quality conclusions remain pending; timely 206 delivery alone is not
a smooth-playback result.

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

## Desktop and submission artifacts

The desktop companion at `f5a91035973c7d8f1c2a20a6a5acd1e22fc70c8e` builds
from a fresh detached checkout with locked dependencies and official Flutter
3.47.2. Its complete unsigned Windows x64 review ZIP includes an isolated-profile
launcher, license and hashes. The normal Release window, Home, Settings, Local
Mode and player menu were captured and visually inspected. This is not physical
Android-to-Windows LAN acceptance. [Desktop PR #279](https://github.com/PeterShanxin/MeowWatch/pull/279)
remains draft. Requested Copilot review returned an account-quota failure and
performed no review; it is neither an approval nor a pending review.

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

Continuous recording began when the local Codex showcase opened. The viewer
labels captured native footage, missing devices and recording gaps. The unchanged
`2fc38317` guide/local-player and purchase source recordings are available there
and have been replayed inside its running 2 fps silent canvas capture. The
118-second Review Preview has a separate browser player. The continuous capture
does not record microphone/desktop or
reconstruct earlier unrecorded development. The final demo will use actual
phone/tablet footage with simple frames; submission screenshots remain unframed.
