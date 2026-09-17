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

## Demonstration media

The **Try a short film** action streams the unmodified
[Sintel official trailer](https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4)
from the Blender Foundation. **© Blender Foundation | sintel.org**.
The [project's sharing terms](https://durian.blender.org/sharing/) license this
movie material under [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/).
The app includes the attribution and source/license links in **Sample film
credits** and its in-app license list. No film bytes or third-party trademarks
are bundled. Source labels use Material icons and provider names; they are not
claims of provider endorsement or webpage extraction support.

Native acceptance and demo recordings use `bee.mp4` from Flutter's
[documentation asset repository](https://github.com/flutter/assets-for-api-docs#origin-of-third-party-content),
which identifies that clip as **CC0 Creative Commons**, originally from
[Pixabay's honey-bee clip](https://pixabay.com/en/videos/honey-bee-insect-bee-flower-flying-211/).
The downloaded source is pinned to SHA-256
`91d703354b3bb77b42dc49152f82548668e981525c89464654cb4ca9f802fffc`.
`tools/android_multi_device/prepare_fixture.sh` repeats its compressed packets
for longer native tests and retains source/license/hash provenance. The clip is
test media; it is not a bundled movie catalog or a streaming-service integration.

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

The optional semantics diagnostic in [`tools/flutter_compat`](tools/flutter_compat/README.md)
contains a fixed patch and regression fixture from Flutter PR #190431 at
`65e4783d8a1019029da88ee2435892ef638a9937`. Copyright 2014 The Flutter Authors.
The original BSD 3-Clause text is retained in
[`LICENSE.flutter`](tools/flutter_compat/LICENSE.flutter), with exact source
provenance beside it. This diagnostic does not change the default Flutter SDK.
