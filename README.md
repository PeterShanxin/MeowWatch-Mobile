# MeowWatch Mobile

**Movie night, even when you're miles apart.**

Android-first MeowWatch: synchronized playback, conversation, and nearby desktop control for couples, friends, and small groups.

This is the mobile counterpart to [MeowWatch for desktop](https://github.com/PeterShanxin/MeowWatch), with a new touch interface, Android playback, lifecycle handling, and subscription flow. **Active development: not yet submission-ready.** See the [acceptance ledger](docs/STATUS.md) for verified capabilities and remaining work.

## Development

Requires Flutter 3.44.0 / Dart 3.12, Java 17 or later, and the Android SDK. Android is the validation target; iOS scaffolding is present but not yet validated.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d <android-device>
flutter build apk --debug
```

The standalone Nearby packages have their own development dependencies and a
required CI job. To run those checks locally as well:

```sh
cd packages/nearby_bridge
dart pub get --enforce-lockfile
dart analyze --fatal-infos
dart test
cd ../nearby_platform
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```

For actual same-host LAN TLS client tests, set `NEARBY_TEST_ADDRESS` and
`NEARBY_TEST_PREFIX` to an address/prefix assigned to a local private adapter.
CI selects one from its real interfaces. Without these, the explicitly marked
LAN cases are skipped; that is not cross-device discovery proof.

Use `--dart-define=REVENUECAT_API_KEY=<public-sdk-key>` for the configured RevenueCat project. A missing billing configuration must report unavailable billing, never simulated premium access. Secret/server keys and signing credentials do not belong in the client or repository.

Windows ARM hosts currently lack official local Android Emulator support. Use an attached Android device or the project's hosted Linux emulator workflow when available; the Android build toolchain and ADB are separate from emulator support.

## Product contract

- Host one **real Together Session per local day** for free. Creating an empty room does not consume it.
- Guests join free. Reconnection and playback-target changes continue the same session.
- RevenueCat `meowwatch_plus` unlocks unlimited hosting.
- Local user-selected files and supported direct media URLs; no DRM bypass.
- Syncplay transport fails closed. Nearby control requires explicit authenticated pairing.

See [product specification](docs/PRODUCT_SPEC.md), [delivery goal](docs/GOAL_BRIEF.md), and [status](docs/STATUS.md).

## License

[AGPL-3.0-only](LICENSE). Portable desktop code retains its original notices and provenance. Third-party packages retain their respective licenses.
