# Physical Android and Windows acceptance — September 25

Runtime: physical OnePlus PLK110, Android 16 / API 36, arm64, with the ordinary
`67d0206` debug Test Store APK. Desktop: ordinary Windows release `3ebba3a`,
running in an isolated review profile on a trusted private Wi-Fi network.
No integration-test entry point or simulated billing adapter was used.

## Observed behavior

| Journey | Result |
| --- | --- |
| First launch | Installed the normal APK, completed the three-step guide and opened Local Player Mode. |
| Local video | The licensed Sintel sample loads and visibly advances on the physical phone. |
| Full screen | Landscape playback fills the display; controls and system bars hide during playback. Back returns to portrait player. |
| Continue Watching | The 19-second / 37% position survives an app process restart. Resuming restores 19 seconds paused, without autoplay. |
| Nearby discovery and pairing | The phone discovers the Windows companion. The camera scan recognizes its invitation; that first attempt expires before desktop approval. A fresh invitation entered through the normal paste UI, followed promptly by explicit desktop approval, pairs successfully. |
| Nearby controls | Phone Play advances the desktop's real player. Pause settles at 26 seconds; back ten seconds produces 16 seconds on both screens; forward ten returns both to 26 seconds paused. |
| Saved pairing | After phone app process restart, the saved desktop reconnects without a new invitation or approval. The desktop remains paused at 26 seconds. |
| Revocation | Desktop Revoke disconnects the phone. Attempting the saved credential again is rejected. Returning to This phone works, with the original Local history preserved. |
| RevenueCat outcomes | The SDK's native Test Store dialog handles cancellation, failed purchase and successful purchase. Success activates Plus. Restore on the same active customer visibly reports “Restored. MeowWatch Plus is active.” after scrolling to its feedback. Plus also remains active after app process restart. |

The successful pairing used the paste path; this report does not claim that the
entire camera-to-approved-pair flow completed in one attempt. The initial
approval timeout was investigated and then avoided by approving within the
existing deadline; transport validation and approval requirements were unchanged.

Two visible issues were found: the device selector retained a verified label
after revocation, and Settings put Restore feedback below the offscreen privacy
section. Both fixes pass hosted Check `36124174769` at `0df32c6`, including their
focused UI regressions. They were not rerun on the released phone. A successful Restore action on
an already active customer does not demonstrate clean-cache recovery; the
separate hosted purchase journey provides that evidence.

## Evidence and limits

App-only native hierarchies, phone screenshots and Windows window-render
captures are retained locally. The paired pause/seek captures show 26, 16 and
26 seconds. Physical Local/fullscreen excerpts are included in the film's
documented source media. Raw personal-device recordings, invitations, device
addresses, diagnostics and pairing material are excluded from Git.

This establishes one physical Android device controlling one physical Windows
player. It does not establish two physical Android Together clients, a desktop
process restart with the same pairing, or a physical Cast receiver. Independent
phone/tablet Together, quota and complete Plus-hosting evidence retain their
documented emulator scope. Test Store evidence is not Google Play billing.

## Test cleanup

At the owner's request the phone was released after the core physical checks.
At 10:36 UTC, the original 30-second screen timeout and charging-awake value
were restored and read back. Developer mode and USB debugging were set to off
and read back. Disabling wireless debugging closed the transport before a final
readback; the subsequent ADB device list and port forwards were empty. The
task-owned ADB server was stopped. The Windows review app exited, its listener
closed, and both specifically named review firewall rules were verified absent.

The last UI-only fixes are validated in hosted checks, not represented as having
been rerun on this now-disconnected physical phone.
