# Windows and hosted Android acceptance — September 25, 2026

The ordinary-client rehearsal [36143500404](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36143500404)
passes at mobile source `213634b`. Product code is unchanged from `0df32c6`.
The accepted runtime is an ordinary API 35 x86_64 Android emulator on GitHub's
Linux runner and the ordinary Windows x64 Release `3ebba3a` running through
x64 emulation on the owner's Windows ARM64 PC. This is not two physical phones.

The Android APK uses `lib/main.dart`, without an integration-test entrypoint.
Its SHA-256 is `a9df2a22537c1589c6b7512ddc509de96f29812dcd49e3bb85d0cd9e88eec794`.
Both clients use a disposable public room on `syncplay.pl:8995`. Desktop actions
were sent only to the verified test window on the secondary monitor; every
action's foreground check remained unchanged. No global mouse, keyboard or
clipboard input was used.

## Observed result

| Action | Independent observation |
|---|---|
| Join and chat | Both ordinary clients show the peer and exchange the exact run-specific stage messages. |
| Android Play | Windows renders changing movie frames and advances from its initial zero position. Its protocol log records the native timeline. |
| Android Pause | Windows holds at 1:16 in two separate original captures. |
| Android Seek | Windows changes to 2:53 while paused. |
| Windows Play | Android's original captures show 2:57 then 3:02 with the Pause control and changing movie frames. |
| Windows Pause | Both clients show 3:54 paused; Android's separate stable-pause receipt retains that position. |
| Windows Seek | Both clients show 4:58 paused with the corresponding decoded movie scene. |

The cloud report has `completed: true` and no failure. Its original PNG/XML
receipts are in the run's `external-room-rehearsal-1` artifact. Separate original
Windows window captures and the native protocol log were retained locally.
These are sampled behavior checks, not frame-perfect synchronization or latency
measurements. An incidental Windows pause while revealing hidden controls was
resumed before the cloud-pause phase; no product state was injected or repaired.

## Media fallback and retained failures

Android plays the [AndroidX Big Buck Bunny test video](https://storage.googleapis.com/exoplayer-test-media-0/BigBuckBunny_320x180.mp4).
Windows plays an unchanged download through the existing loopback-only
byte-range fixture server at `http://127.0.0.1:18775/sync-fixture.mp4`.
The 64,657,027-byte copy has SHA-256
`f78f39603e6774907f2faafabf26a667f4a6fc31769ec304a8a8f7c62d280508`.
Different announced source names leave a visible **Different file** warning on
Windows despite the identical movie. This limitation is retained, not hidden.

Earlier run `36139723441` attempt 1 failed after Windows reported
`ffurl_write returned 0xffffd8ba` on the original remote stream; its exact
underlying network cause was not established. Attempt 2 used the downloaded
copy and demonstrated Android-to-Windows play/pause, but the operator's pause
receipt arrived just after the 90-second manual-reply deadline. Both remain
failed runs. The accepted run allows three minutes per manual reply while
retaining the overall 20-minute deadline and all native playback assertions.

The fallback does not prove Windows remote-source stability. This public-room
check also does not establish LAN discovery, Cast receiver behavior, physical
two-Android synchronization or later builds. [Physical Nearby acceptance](PHYSICAL_ACCEPTANCE_2026-09-25.md)
and the [complete ordinary-APK phone/tablet rehearsal](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36137630270)
retain their separate scopes. The maintainer confirmed this two-instance check
on September 25 and authorized desktop PR #279 closeout at unchanged source
`3ebba3a`. The PR was merged as `3b8b976`; its application source matches the
accepted build. [Signed release `v0.51.0-alpha`](https://github.com/PeterShanxin/MeowWatch/releases/tag/v0.51.0-alpha)
passes [release run 36147584974](https://github.com/PeterShanxin/MeowWatch/actions/runs/36147584974).
R2 latest/changelog contain the version and the public ZIP is reachable. The
GitHub ZIP matches R2's checksum and its version-bound Ed25519 signature verifies
against the public key baked into the app. The release was not relaunched for
another manual test; unchanged application source preserves the accepted check.

After inspection, the owned Windows review process and loopback media server
were closed at 14:16 UTC. Both processes and their children were absent and
port 18775 was no longer listening. The physical phone stayed released.
