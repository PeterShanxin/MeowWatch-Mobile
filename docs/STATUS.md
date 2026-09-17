# Delivery status

Last updated: 2026-09-17. **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Partial | Baseline install 35219098539 passes debug API 29 and release API 35, including confirmed URL/content sharing. Debug API 35 fails when its native observer cannot obtain a complete tree. Final judging APK/signing audit remains |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public AGPL-3.0 repository exists. Gitleaks 8.30.1 finds zero findings in 465 tracked files and 43 all-ref commits at d946d1b. Later edits and final release contents need their own review |
| 3 | Clear first-launch create/join | Partial | Baseline Together reaches real creation/join and media/social actions. Baseline five-layout journey passes 3/5 complete drivers; isolated SDK candidate passes 5/5 on the same source tree. Camera hardware and full extended Together acceptance remain open |
| 4 | Two real clients repeatedly play/pause/seek in sync | Partial | Baseline matrix 35219098750 passes all jobs. Full Together 35219098687 completes basic two-way control and shared-link playback, then fails during recovery Play. Run-specific participant names are now used for a fresh baseline/candidate comparison; no whole journey pass yet |
| 5 | Real-session chat/reactions/presence | Partial | Baseline Together reaches rendered chat/reactions/presence and shared-link playback without a detected ANR. Current purchase proves the premium reaction reaches its TLS peer. Recovery, repeated-room branches and final paired-film acceptance remain open |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | SAF relaunch passes again in 35219098707. Normal lifecycle 35219098578 fails its genuine recording-tail coverage check before HOME/resume/restart acceptance. Together displays a 404 error but fails the subsequent recovery Play. Neither failed run proves completed recovery |
| 7 | Local Mode and Continue Watching | Partial | Baseline native playback and SAF pass. All five baseline product layouts record 20 app steps/14 screenshots, but phone and landscape tablet fail teardown. Candidate SDK completes all five layouts; that separate result does not upgrade baseline acceptance |
| 8 | Secure phone-to-desktop discovery/pair/control | Partial | Android Nearby 35219098609 passes same-device transport/storage/discovery checks. Earlier Windows native probes remain valid within their scope. Physical Android-to-Windows LAN proof remains open |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | Purchase 35219098642 passes 12 stages: one free plus two distinct paid hosts, cancel/failure/success, same-customer restore, both premium themes and peer-received reaction. Latest accepted real expiry remains 9b7e9ed/35212468121; d946 expiry was cancelled. Physical billing and lost-identity recovery remain separate gates |
| 10 | Correct daily quota and session continuity | Partial | Fresh purchase proves one free plus two paid sessions; baseline hosting/quota matrix passes. Extended room-history resume/new-room replay is not reached after Together recovery fails, and normal lifecycle continuity remains unaccepted |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | Baseline passes small phone, portrait tablet and landscape phone; phone and landscape tablet fail semantics teardown after all app steps. Same-tree candidate passes 5/5 complete drivers with a verified temporary SDK patch. Final artifact review, adoption decision and physical QA remain |
| 12 | Reliable Cast or exact blocker and fallback | Partial | Android sender and same-room handoff remain implemented; release builds pass their scoped checks. Actual receiver acceptance remains open |
| 13 | No placeholders, dead ends or silent failures | Partial | Native purchase/premium, sample/history, accepted API 29 debug/API 35 release sharing, peer-link playback and a visible 404 error have evidence. Recovery Play, repeat-room flow, baseline semantics teardown, debug API 35 observation and complete lifecycle recording remain unresolved |
| 14 | Clean-install full demo rehearsal | Partial | d946 baseline cohort has 6 passing, 4 failed and 1 cancelled workflow. Candidate five-layout pass is separate. Together's final phone segment has one frame/zero duration and fails composition; lifecycle recording misses its tail. No complete rehearsal or accepted paired film |
| 15 | Shipaton submission confidence | Partial | Entrant prerequisites and prepared brand/submission assets retain their recorded evidence. Latest purchase acceptance is separate from older reviewed demo-source clips. Final film, full rehearsal, physical gates and remaining eligibility/legal checks remain |

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

## Execution order

1. Secure Syncplay + actual Android playback vertical slice.
2. Room flow, social layer, persistent history, lifecycle recovery.
3. Authenticated Nearby protocol, mobile client, isolated desktop companion PR.
4. Real RevenueCat Test Store, daily hosting quota, rendered UI/accessibility polish.
5. Cast, QR/deep links/share intents, peer URLs, themes and repeated-session flow.
6. Clean checkout/install, device tests, CI, public repository review, final demo/assets.

## Human/external dependencies

- The entrant confirmed on 2026-09-17 that they are an active student, have reached the local age of majority and have a student/academic email available for Devpost. Domain recognition, other eligibility conditions and final legal acceptance are separate checks; no email address was collected.
- RevenueCat login and Test Store/catalog setup completed; email confirmation banner remains.
- Android SDK license accepted by the user; official SDK/ADB/build tools installed and actual APK builds pass on Windows ARM.
- Physical Android/Cast hardware availability is unconfirmed. Do not label emulator tests as real-device proof.

## Work ownership

Integration, application, mobile playback and final acceptance remain with the main agent. Bounded workers own protocol, Android environment, billing policy and official-rule research. Shared manifests and lockfiles have one owner.

## Live development recording

The user requested continuous recording from the point the local Codex showcase opened, followed by a professional multi-device demo. The local viewer must label missing-device states and any recording gaps. Final native recordings should show actual phone/tablet clients with simple frames; submission screenshots must also be exported without frames. Earlier unrecorded development is not reconstructed as footage.
