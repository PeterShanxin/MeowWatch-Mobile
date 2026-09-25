# External room ordinary guest rehearsal

This manual gate pairs one **ordinary** `lib/main.dart` debug APK on a fresh
hosted API 35 Pixel 6 emulator with a person operating the ordinary Windows
MeowWatch client. It uses the public `syncplay.pl:8995` endpoint and the
[Big Buck Bunny MP4](https://storage.googleapis.com/exoplayer-test-media-0/BigBuckBunny_320x180.mp4)
used by [AndroidX's native media test activity](https://android.googlesource.com/platform/frameworks/support/+/0c3df10399d72871a0706423b30a7bb75dc8b36a/graphics/filters/filters/src/androidTest/kotlin/androidx/graphics/filters/TestFiltersActivity.kt).
The approximately 10-minute Blender film is [CC BY 3.0](https://peach.blender.org/about/).
The Windows client must join the same disposable room and load that exact URL.
No test entry point, app-state injection, LAN connection or desktop control is
used. The GitHub job itself takes at most 45 minutes including build; the guest
journey has a 20-minute limit beginning before ordinary app launch.

Before installing either APK, this job reuses the dual-device suite's bounded
SDK setup preparation and read-only resource admission. Preparation verifies
the exact owned AVD and may recover one eligible Google SDK setup/launcher ANR;
all original receipts remain in the artifact. Any other failure stops the run.
No system-dialog recovery is permitted during the ordinary application journey.

Push the reviewed source to the dedicated `test/external-room-rehearsal` branch
to run before the workflow exists on the default branch. Its room code is
`mw-cloud-<GitHub Actions run ID>`; the workflow summary publishes that code
and the deterministic `MWG-<first 8 hex digits of SHA-256(room code)>-` chat
prefix. After the workflow lands on the default branch, manual
`workflow_dispatch` accepts a disposable 3–36-character ASCII room code.
Only letters, digits, dots, underscores and hyphens are accepted.

The Windows operator sends each exact prefixed chat message **after** seeing
the relevant state in the ordinary client. Wait for the next cloud message or
acknowledgment before acting again:

| Cloud message | Windows action and reply |
| --- | --- |
| `READY` | Confirm same room and media; send `DESKTOP_READY`. |
| `CLOUD_PLAY` | Confirm Windows playback and advancing timeline; send `SAW_CLOUD_PLAY`. |
| `CLOUD_PAUSE` | Confirm Windows paused timeline; send `SAW_CLOUD_PAUSE`. |
| `CLOUD_SEEK` | Confirm Windows timeline around three minutes; send `SAW_CLOUD_SEEK`. |
| `READY_DESKTOP_PLAY` | Press Play in Windows, then send `DESKTOP_PLAY`; await `SAW_DESKTOP_PLAY`. |
| `SAW_DESKTOP_PLAY` | Press Pause in Windows, then send `DESKTOP_PAUSE`; await `SAW_DESKTOP_PAUSE`. |
| `SAW_DESKTOP_PAUSE` | Seek in Windows to about five minutes, then send `DESKTOP_SEEK`; await `SAW_DESKTOP_SEEK`. |

For example, if the summary displays prefix `MWG-1234abcd-`, send
`MWG-1234abcd-DESKTOP_READY`. The initial chat and each later reply also prove
desktop-to-cloud text delivery in the visible guest chat. Keep a separate
Windows screenshot or log at each `SAW_CLOUD_*` reply; the guest artifact alone
cannot prove what the desktop rendered. Never use a personal room or chat.

`build/external-room-rehearsal/evidence/result.json` records APK SHA-256,
emulator identity, phase receipts, completion or precise failure. Each passed
transition has an original PNG, native XML hierarchy and focused-window dump;
the last failed phase has diagnostic originals. A green result proves this
specific hosted Android–Windows public-room rehearsal only. It cannot prove
physical Android behavior, LAN/Nearby, Cast or a later build.

The joined-room screen alone is only a connection receipt. The exact
`DESKTOP_READY` and later desktop chat messages, followed by native playback
changes, are the independent evidence that the manually operated peer was in
the same room.
