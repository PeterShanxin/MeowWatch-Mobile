# Delivery status

Last updated: 2026-09-16. **In development; not submission-ready.**

The controlling inputs are [Goal Brief](GOAL_BRIEF.md) and [Product Spec](PRODUCT_SPEC.md). P0/P1/P2 define order, not scope cuts.

## Acceptance evidence

| # | Required outcome | Status | Evidence / next check |
|---|---|---|---|
| 1 | Clean checkout builds and installs | Partial | Local normal and integration-test debug APKs build; clean-checkout/install proof pending |
| 2 | Public, licensed, documented, secret-free repository | Partial | Public repository exists; bootstrap in progress |
| 3 | Clear first-launch create/join | Unverified | Implementation pending |
| 4 | Two real clients repeatedly play/pause/seek in sync | Partial | Two real public TLS clients pass protocol smoke; Android video clients pending |
| 5 | Real-session chat/reactions/presence | Unverified | Implementation pending |
| 6 | Disconnect/reconnect/lifecycle recovery | Partial | Socket recovery and session-race tests pass; Android lifecycle matrix pending |
| 7 | Local Mode and Continue Watching | Partial | Production target builds; room-scoped disk history and controller resume tests pass; Android runtime pending |
| 8 | Secure phone-to-desktop discovery/pair/control | Unverified | Contract and focused desktop PR pending |
| 9 | RevenueCat purchase, entitlement, unlimited hosting, restore | Partial | Real Test Store/catalog configured; official SDK builds; actual purchase verification pending |
| 10 | Correct daily quota and session continuity | Partial | 19 billing/quota tests pass; integrated device quota funnel pending |
| 11 | Rendered phone, small phone, tablet and rotation QA | Unverified | Local Windows ARM emulator unsupported; device/hosted emulator path being prepared |
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

- `flutter test --no-pub --reporter expanded`: **402 passed**, including protocol, billing/quota, disk history and controller race regressions.
- `flutter build apk --debug --no-pub`: passes on the local Windows ARM host.
- `flutter build apk --debug --no-pub -t integration_test/playback_smoke_test.dart`: passes on the same host.
- `dart run test/support/syncplay_live_smoke.dart`: two public STARTTLS clients; bidirectional control, social signals, presence and reconnection. See [SYNC_CORE.md](SYNC_CORE.md).
- The launch UI is still scaffold code. APK compilation does not establish a finished app or rendered UX quality.
- Hosted Android playback/texture/recording workflow is prepared but has not yet produced runtime evidence.

## Live development recording

The user requested continuous recording from the point the local Codex showcase opened, followed by a professional multi-device demo. The local viewer must label missing-device states and any recording gaps. Final native recordings should show actual phone/tablet clients with simple frames; submission screenshots must also be exported without frames. Earlier unrecorded development is not reconstructed as footage.
