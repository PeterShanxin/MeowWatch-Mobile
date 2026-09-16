# Third-party notices

MeowWatch is licensed under **AGPL-3.0-only**. The complete application
license is in [`LICENSE`](LICENSE), and the corresponding source is published
at <https://github.com/PeterShanxin/MeowWatch-Mobile>.

## Adapted desktop MeowWatch code

The portable Syncplay protocol, room, chat and synchronization code is adapted
from desktop MeowWatch at commit
[`c7cc4be5203abe28fb1cd043c286367fd1e3ba46`](https://github.com/PeterShanxin/MeowWatch/tree/c7cc4be5203abe28fb1cd043c286367fd1e3ba46).
That code is also licensed under **AGPL-3.0-only**. See
[`docs/SYNC_CORE.md`](docs/SYNC_CORE.md) for the exact provenance and mobile
adaptations.

## Bundled fonts

- **DM Sans** — Copyright 2014 The DM Sans Project Authors. Licensed under the
  SIL Open Font License 1.1. The complete text is in
  [`assets/fonts/DMSans-OFL.txt`](assets/fonts/DMSans-OFL.txt).
- **DM Serif Display** — Copyright 2014–2018 Adobe, with Reserved Font Name
  “Source”; Copyright 2019 Google LLC. Licensed under the SIL Open Font
  License 1.1. The complete text is in
  [`assets/fonts/DMSerifDisplay-OFL.txt`](assets/fonts/DMSerifDisplay-OFL.txt).

## Flutter and Dart packages

The app uses Flutter and the packages locked by `pubspec.lock`. Flutter’s
built-in license page displays the complete license texts bundled by the
Flutter SDK and those packages. The direct runtime packages include:

| Package | License in the resolved package |
|---|---|
| Flutter SDK | BSD 3-Clause |
| `app_links` | Apache License 2.0 |
| `crypto` | BSD 3-Clause |
| `file_picker` | MIT |
| `meta` | BSD 3-Clause |
| `mobile_scanner` | BSD 3-Clause |
| `path` | BSD 3-Clause |
| `path_provider` | BSD 3-Clause |
| `purchases_flutter` | MIT, Copyright 2019 RevenueCat |
| `qr_flutter` | BSD 3-Clause |
| `share_plus` | BSD 3-Clause |
| `shared_preferences` | BSD 3-Clause |
| `video_player` | BSD 3-Clause |

`nearby_bridge` and `nearby_platform` are unpublished packages maintained
inside this repository and are covered by the repository’s AGPL-3.0-only
license. Transitive dependencies and platform implementations remain under
their own license terms, shown in the in-app license page and distributed
package license files.
