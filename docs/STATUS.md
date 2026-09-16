# Delivery status

Last updated: 2026-09-16. **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Partial | Local normal and integration-test debug APKs build; clean-checkout/install proof pending |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public repository exists; bootstrap in progress |
| 3 | Clear first-launch create/join | Partial | Production screens and local validation implemented; Android journey pending |
| 4 | Two real clients repeatedly play/pause/seek in sync | Partial | Two real public TLS clients pass protocol smoke; first native phone/tablet job stopped before launch at SDK tool lookup; corrected rerun pending |
| 5 | Real-session chat/reactions/presence | Partial | Public TLS protocol smoke passes; production chat UI implemented; dual Android evidence pending |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | Socket recovery and session-race tests pass; Android lifecycle matrix pending |
| 7 | Local Mode and Continue Watching | Partial | Native decoder/play/pause/seek/reopen pass; disk history/controller resume tests pass; integrated UI journey pending |
| 8 | Secure phone-to-desktop discovery/pair/control | Unverified | Contract and focused desktop PR pending |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | Native Test Store cancel/failure/success, Plus activation, server refresh and restore pass in run 35057627571; integrated unlimited-hosting funnel pending |
| 10 | Correct daily quota and session continuity | Partial | 19 billing/quota tests pass; integrated device quota funnel pending |
| 11 | Rendered phone, small phone, tablet and rotation QA | Partial | Twelve Flutter test-renderer PNGs across four viewports plus 200% text/player/keyboard regression checks pass; native product screenshots pending |
| 12 | Reliable Cast or exact blocker and fallback | Unverified | Scheduled after core stability |
| 13 | No placeholders, dead ends or silent failures | Unverified | Final product review pending |
| 14 | Clean-install full demo rehearsal | Unverified | Pending integrated application |
| 15 | Shipaton submission confidence | Unverified | Rules research and submission assets pending |

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

- `flutter test --no-pub --reporter expanded`: **428 passed**, including four rendered-layout cases and four player/chat accessibility cases. The latter reproduce and protect fixes for 200% text, long playback times and landscape keyboards.
- `flutter build apk --debug --no-pub`: passes with the production UI and bundled fonts on the local Windows ARM host.
- `flutter build apk --debug --no-pub -t integration_test/playback_smoke_test.dart`: passes on the same host.
- `dart run test/support/syncplay_live_smoke.dart`: two public STARTTLS clients; bidirectional control, social signals, presence and reconnection. See [SYNC_CORE.md](SYNC_CORE.md).
- Production onboarding, home, join, player, chat, invitation, media, settings and real-offering paywall screens are implemented. Nearby and Cast remain unfinished; this is not a submission-ready build.
- [Native Android playback run 35054195277](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35054195277) passed on an API 35 Pixel 6 x86_64 AVD. Actual video texture screenshots and a 44.17-second native recording were inspected: 1280×720 media decoded, play advanced 773 ms, and seek reached 2018 ms. This is emulator evidence, not physical-device proof.
- The product runtime matrix builds distinct host/guest APKs and is designed to record both concurrent AVDs and exercise Test Store cancel/failure/success. The first run exposed SDK-path and native-focus-query issues before those behaviors completed. Both runner fixes have targeted checks; native rerun evidence is pending.
- The clean-install product journey covers onboarding, local media playback, seek, durable Continue Watching and the real offering on four Android viewports. Its integration APK builds locally; hosted native execution is pending.
- [Native RevenueCat job 104671008222](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35057627571/job/104671008222) passed: real `default` offering, `$rc_monthly`, localized `$2.99`, initial entitlement false, cancel code 1, failure code 42, successful purchase activates `meowwatch_plus`, server refresh and restore retain it. Native dialog screenshots and three recordings were retained. This uses the official Test Store on an emulator; it does not prove a Play Store charge, physical-device billing, or the integrated hosting funnel.

## Live development recording

The user requested continuous recording from the point the local Codex showcase opened, followed by a professional multi-device demo. The local viewer must label missing-device states and any recording gaps. Final native recordings should show actual phone/tablet clients with simple frames; submission screenshots must also be exported without frames. Earlier unrecorded development is not reconstructed as footage.
