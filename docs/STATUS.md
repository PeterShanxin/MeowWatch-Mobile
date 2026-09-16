# Delivery status

Last updated: 2026-09-16. **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Partial | Local normal and integration-test debug APKs build; clean-checkout/install proof pending |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public repository exists; bootstrap in progress |
| 3 | Clear first-launch create/join | Partial | Native onboarding, home and invalid-join recovery pass on five phone/tablet viewports; two-user production-room rehearsal pending |
| 4 | Two real clients repeatedly play/pause/seek in sync | Partial | Two independent API 35 AVDs boot and play native video; pause assertion exposed a sampling race during authoritative seek correction; convergence-aware rerun pending |
| 5 | Real-session chat/reactions/presence | Partial | Public TLS protocol smoke passes; production chat UI implemented; dual Android evidence pending |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | Socket recovery and session-race tests pass; Android lifecycle matrix pending |
| 7 | Local Mode and Continue Watching | Partial | Native production journey passes local URL play/pause/seek and durable Continue Watching on five viewports; SAF picker/relaunch APK builds and hosted native execution is next |
| 8 | Secure phone-to-desktop discovery/pair/control | Partial | Mobile UI/target handoff, pinned TLS and isolated desktop companion implemented; Windows and Android native secure storage survive process restarts and persist revocation; Android NSD discovery passes; cross-device LAN proof pending |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | Native Test Store cancel/failure/success, Plus activation, server refresh and restore pass in run 35057627571; integrated unlimited-hosting funnel pending |
| 10 | Correct daily quota and session continuity | Partial | 19 billing/quota tests pass; integrated device quota funnel pending |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | Five native viewports pass and critical screenshots inspected, including both tablet orientations and landscape phone; first-run, player, continue and paywall screens verified; room/Nearby native visual review remains |
| 12 | Reliable Cast or exact blocker and fallback | Unverified | Scheduled after core stability |
| 13 | No placeholders, dead ends or silent failures | Unverified | Final product review pending |
| 14 | Clean-install full demo rehearsal | Unverified | Pending integrated application |
| 15 | Shipaton submission confidence | Unverified | Official rules and Test Store acceptance researched; final assets, eligibility confirmation and full rehearsal remain |

## Execution order

1. Secure Syncplay + actual Android playback vertical slice.
2. Room flow, social layer, persistent history, lifecycle recovery.
3. Authenticated Nearby protocol, mobile client, isolated desktop companion PR.
4. Real RevenueCat Test Store, daily hosting quota, rendered UI/accessibility polish.
5. Cast, QR/deep links/share intents, peer URLs, themes and repeated-session flow.
6. Clean checkout/install, device tests, CI, public repository review, final demo/assets.

## Human/external dependencies

- RevenueCat login and Test Store/catalog setup completed; email confirmation banner remains.
- Android SDK license accepted by the user; official SDK/ADB/build tools installed and actual APK builds pass on Windows ARM.
- Physical Android/Cast hardware availability is unconfirmed. Do not label emulator tests as real-device proof.

## Work ownership

Integration, application, mobile playback and final acceptance remain with the main agent. Bounded workers own protocol, Android environment, billing policy and official-rule research. Shared manifests and lockfiles have one owner.

## Current checkpoint evidence

- `flutter test --no-pub --reporter expanded`: **499 passed** with an actual local private adapter selected for TLS client tests; no LAN skips. Full `flutter analyze --no-pub` reports no issues. Tests include five rendered layouts, 200% text, long player times, landscape keyboards and paywall accessibility.
- `flutter build apk --debug --no-pub`: passes with the production UI and bundled fonts on the local Windows ARM host.
- `flutter build apk --debug --no-pub -t integration_test/playback_smoke_test.dart`: passes on the same host.
- `dart run test/support/syncplay_live_smoke.dart`: two public STARTTLS clients; bidirectional control, social signals, presence and reconnection. See [SYNC_CORE.md](SYNC_CORE.md).
- Production onboarding, home, join, player, chat, invitation, media, settings, Nearby and real-offering paywall screens are implemented. Nearby still needs cross-device acceptance and Cast work continues; this is not a submission-ready build.
- [Native Android playback run 35054195277](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35054195277) passed on an API 35 Pixel 6 x86_64 AVD. Actual video texture screenshots and a 44.17-second native recording were inspected: 1280×720 media decoded, play advanced 773 ms, and seek reached 2018 ms. This is emulator evidence, not physical-device proof.
- [Two-AVD run 35058753994, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35058753994) booted independent phone/tablet clients and played native video. It failed when a pause stability assertion sampled before the subsequent authoritative seek had converged. The corrected test waits for both pause and the actual native position, then retains the original 350ms drift bound. It has not yet passed; recordings are development evidence.
- [Native production journey run 35061089564](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35061089564) passes onboarding, local playback, seek, durable Continue Watching and the real offering on all five viewports: phone, small phone, portrait tablet, landscape tablet and landscape phone. All five results have exit 0, seven native screenshots and a raw screen recording. Critical images were inspected; the prior safe-area overflow and paused buffering indicator are fixed, tablet home uses two columns, and the offering shows its monthly price period. This remains AVD evidence.
- [Native RevenueCat job 104671008222](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35057627571/job/104671008222) passed: real `default` offering, `$rc_monthly`, localized `$2.99`, initial entitlement false, cancel code 1, failure code 42, successful purchase activates `meowwatch_plus`, server refresh and restore retain it. Native dialog screenshots and three recordings were retained. This uses the official Test Store on an emulator; it does not prove a Play Store charge, physical-device billing, or the integrated hosting funnel.
- Nearby packages: **76 pure Dart primitive/authority/TLS client/server tests** and **14 protected-store/discovery contract tests** pass. Self-revocation immediately retires control and acknowledges success only after durable storage; failure/timeout never returns success. These counts are not all hardware tests.
- The isolated Windows Release native probe passed three separate processes: protected identity/credential write, restart/read/revoke, and restart/revocation persistence. Actual network-profile enumeration reports a Public network and correctly rejects eligibility. No network-profile or firewall setting was changed. The actual Release MediaKit probe also passes all ten dispatch checks after fixing a stale decode-probe marker that incorrectly sought back to EOF during replay: playback advances 500ms, paused drift is 0ms, seek reaches 1614ms exactly, and replay advances from zero to 266ms. This tests native player dispatch, not paired cross-device transport.
- [Android Nearby run 35061089690](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35061089690) passes protected identity/credentials, namespace isolation, two process restarts and persistent revocation. It also verifies native private-interface enumeration and discovers its real NSD advertisement. A same-device Android TLS pair/auth/control/revoke extension is ready for a subsequent run; neither gate substitutes for Android-to-Windows LAN evidence.
- Product matrix run 35061089615 exposed three separate issues: a Pixel Launcher ANR obscured the billing dialog, two decoders in the same-process hosting harness competed for audio focus, and the dual-AVD host never attached to its VM service. The first two have narrow test-environment corrections with unchanged product assertions; host launch diagnosis continues. No failing run is counted as accepted co-watch evidence.
- Linux TLS revocation receipt delivery now closes the output gracefully while draining remaining input before a bounded hard close, avoiding a reset that discarded the success receipt. The complete 76-test protocol suite passes on Linux as well as Windows.
- Python native billing, hosting-purchase and Nearby runners pass **28 tests**. The new integrated hosting funnel combines real RevenueCat, production quota/controller, public TLS clients and native video; native execution is pending. Its same-process service reopen is not claimed as OS process-restart evidence.

## Live development recording

The user requested continuous recording from the point the local Codex showcase opened, followed by a professional multi-device demo. The local viewer must label missing-device states and any recording gaps. Final native recordings should show actual phone/tablet clients with simple frames; submission screenshots must also be exported without frames. Earlier unrecorded development is not reconstructed as footage.
