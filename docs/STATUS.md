# Delivery status

Last updated: 2026-09-17. **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Partial | ec856b5 install passes debug API 29 and release API 35 with URL/content sharing. Debug API 35 fails on an incomplete observer tree while the original screenshot still shows the review dialog. Bounded recapture is prepared; final APK audit remains |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public AGPL-3.0 repository. Gitleaks at ec856b5 reports zero findings in 466 tracked files and 48 all-ref commits. New changes and final artifacts require fresh checks |
| 3 | Clear first-launch create/join | Partial | First-use guide, Settings replay, supported-source labels and licensed sample are implemented. Native room creation/join has evidence. ec856 five-layout journey passes 3/5 complete drivers; both tablet drivers fail framework teardown after their app steps |
| 4 | Two real clients repeatedly play/pause/seek in sync | Partial | ec856 runtime matrix passes. Candidate Together reaches two native clients and shared media, but recovery Play is obstructed by an old error Snackbar. New app fix has a failing-baseline/passing-fixed regression; full native repeat remains |
| 5 | Real-session chat/reactions/presence | Partial | Paired native chat/reactions/presence and shared-link playback have evidence. d946 production purchase proves peer-received premium reaction. Extended room replay and final paired film remain open |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | ec856 SAF relaunch passes. Normal lifecycle recording fails its tail gate before HOME. Shared-link recovery Snackbar and modal ordering are corrected locally; complete native lifecycle/recovery proof remains |
| 7 | Local Mode and Continue Watching | Partial | ec856 native playback and SAF pass. All five layout reports contain 20 app steps and 14 screenshots each, but two tablet drivers fail teardown; these reports do not override driver failure |
| 8 | Secure phone-to-desktop discovery/pair/control | Partial | ec856 Android Nearby passes within its emulator boundary. Desktop f5a9103 clean Release builds and its actual Windows UI was inspected. Physical Android-to-Windows discovery/pair/control/revoke/restart proof remains open |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | d946 production purchase passes 12 stages including one free and two paid hosts. ec856 real Test Store process relaunch, same-customer restore, fresh SDK expiry and restore remaining inactive pass. ec856 production purchase fails recording coverage; physical/lost-identity recovery remain separate |
| 10 | Correct daily quota and session continuity | Partial | ec856 hosting/quota runtime matrix passes. d946 production purchase proves free and paid sessions. Extended history/new-room replay and normal lifecycle continuity remain unaccepted |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | ec856 passes phone, small phone and landscape phone; tablet and landscape tablet fail semantics teardown after all app steps. Earlier isolated SDK candidate passes five layouts, but does not fix Together geometry; patch remains unadopted |
| 12 | Reliable Cast or exact blocker and fallback | Partial | Android sender and same-room handoff are implemented. Actual receiver acceptance awaits hardware; phone playback fallback is available |
| 13 | No placeholders, dead ends or silent failures | Partial | Actual sample/history, sharing and visible playback errors have evidence. Snackbar recovery/modal transitions have local fixes. Framework geometry, complete recording and final clean-install retry remain open |
| 14 | Clean-install full demo rehearsal | Partial | ec856 baseline has 6 passing and 5 failed workflows. Separate candidate Together also fails. No complete rehearsal or accepted paired film; lower-cost capture retains every timing gate |
| 15 | Shipaton submission confidence | Partial | Brand kit and original-size submission screenshot are prepared. Final under-two-minute film, full rehearsal, physical gates and remaining eligibility/legal checks remain open |

## Latest completed native cohort: ec856b5

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

## Local verification of the subsequent fixes

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
frame. The reviewed-source purchase chapter is 43 seconds, with Test Store and
headless-peer boundaries disclosed. An accepted complete paired film and the
full clean-install rehearsal remain open. Historical runs and asset provenance
are preserved in [Acceptance history](ACCEPTANCE_HISTORY.md).

## Human/external dependencies

- The entrant confirmed active student status, local age of majority and access to an academic email. Remaining residency/ownership/conflict conditions and final legal acceptance are separate checks.
- RevenueCat login/Test Store catalog setup and user acceptance of the Android SDK license are complete. RevenueCat email confirmation remains visible.
- Physical Android, trusted physical LAN and Cast receiver availability remain unconfirmed. Emulators and virtual network adapters are not substituted for this evidence.
- Desktop required native/manual review gates remain applicable before merge or release.

## Live development recording

Continuous recording began when the local Codex showcase opened. The viewer
labels captured native footage, missing devices and recording gaps. Its 2 fps
silent canvas stream remains running; it does not capture microphone/desktop or
reconstruct earlier unrecorded development. The final demo will use actual
phone/tablet footage with simple frames; submission screenshots remain unframed.
