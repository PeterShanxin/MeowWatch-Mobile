# MeowWatch Mobile

Read `docs/GOAL_BRIEF.md`, `docs/PRODUCT_SPEC.md`, and `docs/STATUS.md` before substantial changes.

- Android-first Flutter app. Keep protocol and quota logic independent of widgets.
- License: AGPL-3.0-only. Preserve attribution for code reused from desktop MeowWatch.
- Never weaken STARTTLS validation or expose unauthenticated LAN commands.
- One real free hosted Together Session per local day; joining, reconnecting, and target changes are not new sessions.
- Real RevenueCat entitlement controls Plus. Never substitute simulated purchases in production.
- Keep changes scoped, preserve other workers' files, and never edit the desktop reference checkout.
- Checks: `dart format --output=none --set-exit-if-changed lib test integration_test`, `flutter analyze`, `flutter test`, `flutter build apk --debug`.
- Device/emulator evidence must name the actual runtime. Widget tests do not establish hardware, LAN, purchase, or Cast correctness.
- Keep evidence and outstanding criteria current in `docs/STATUS.md`. Do not mark submission-ready until all practical acceptance criteria have fresh proof.
- Do not commit credentials, local logs, signing keys, or personal test data.
