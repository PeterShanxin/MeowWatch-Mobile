# MeowWatch Mobile — submission film

The current Remotion edit is **94 seconds**, using actual Android phone/tablet recordings
from the frozen product source. It covers Start/Join, shared playback controls,
conversation, Local Mode resume and the real RevenueCat Test Store purchase,
Restore and Plus features. [Remotion export 36112159786](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36112159786)
at `efec08e` passes: 1920 × 1080, H.264, 30 fps and an AAC music track. The
composition is 2,820 frames; encoded duration includes normal audio padding.
It adds a kinetic branded opening, alternating device layouts, restrained focus
changes and an original synthesized 120 BPM score. The editable project is in
[showcase/remotion](../showcase/remotion/README.md). Critical scenes and a short
moving Studio preview are inspected. Full editorial review and a publicly
playable final video link remain open. This is not a submission-ready declaration.

The earlier silent export [36106912082](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36106912082)
at `7bcd6f4` remains a private YouTube review upload. It is 94.000 seconds and
3,925,136 bytes; its full decoding passed in hosted CI. The Remotion edition
supersedes its presentation while retaining the same source intervals.

[Edit decision list](demo/submission-final.edl.json) ·
[Exact source artifacts](demo/submission-final.edl.sources.json) ·
[Remaining acceptance](STATUS.md)

## Story and cuts

| Film time | What the viewer sees |
| --- | --- |
| 0–4 | Movie night, even miles apart. |
| 4–12 | Start a room on the phone. |
| 12–20 | A tablet joins the same room. |
| 20–45 | Actual two-way play, pause and seek. |
| 45–51 | Messages beside the shared movie. |
| 51–61 | Local Mode returns paused at the saved place, then explicit Play. |
| 61–65 | One free hosted session per local day; guests always join free. |
| 65–71 | Native Test Store purchase and Plus activation. |
| 71–75 | Restore in Settings for the same active customer. |
| 75–79 | Select Glass Aurora. |
| 79–84 | Send the premium Movie night reaction. |
| 84–89 | A second Plus session in Cinema Noir. |
| 89–94 | The new Android counterpart to open-source MeowWatch. |

All clips run at 1×. Thin device frames and captions sit outside the complete
capture. Paired clips retain their shared approximate recording clock; neither
device is independently retimed. Native held frames and latency remain visible.
This is an edited feature demonstration from separate journeys and binaries,
not one uninterrupted take. The footage uses the CC0 Bee fixture; licensing
and the separate in-app Sintel sample are in [third-party notices](../THIRD_PARTY_NOTICES.md).

## Source and runtime

- Phone/tablet: [36101169078](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36101169078)
  at `5f5dd7f`, two independent API 35 emulators, production UI integration builds.
  All 26 host and 25 guest stages passed. Original 432 × 960 phone and 960 × 600
  tablet recordings are used.
- Local Mode: [36103033022, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36103033022/attempts/2)
  at `67d0206`, normal `lib/main.dart` release APK on an API 35 emulator. It
  preserves 69 seconds across a new process, waits paused and resumes only on
  explicit Play. No setup ANR repair or observation timeout occurred.
- Purchases: [36103033131](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36103033131)
  at `67d0206`, native phone UI and RevenueCat SDK/Test Store with a headless TLS
  peer. Cancellation, failure, success, same-customer Restore, premium appearance
  and reaction, and two distinct Plus hosts passed. No real charge occurs.

There are no `lib`, `android` or `assets` changes between `5f5dd7f` and
`67d0206`. The later commits update the network verifier and documentation.
Full hashes, source intervals and artifact names are in the EDL. Selected
original screens and representative output frames have been inspected, including
the final free-host explanatory card. Full editorial review is still open.
The earlier silent export's SHA-256 is
`20926535cb81b2f07d685674d7603360914b45c3eb798678d08bf463d1c08750`.

Physical Android-to-Windows Nearby and receiver Cast acceptance remain open.
They are not depicted as demonstrated features. The app still includes native
fullscreen playback. The final-source phone and tablet fullscreen gate
`36103033180` passed after unchanged reruns; the earlier observer/recording
failures remain recorded in STATUS. The frozen film does not add another clip.

## Render and publish

Run **Remotion submission film** for the current edition. It prepares the original
clips, generates the original score and renders on hosted Ubuntu with two workers.
Its separate preview artifact can be downloaded into the project's `public/`
directory to use Studio without local transcoding.

For the earlier silent edition, run the existing **Check** workflow with
`submission_edit=docs/demo/submission-final.edl.json` on the branch containing the
EDL. Rendering, exact-source checks and full decoding run on hosted GitHub
Actions. No emulator starts in the rendering job. Its artifact includes the
film, EDL, source receipts and static review frames.

Before publication, inspect the complete film at normal speed, check the final
encoded duration is below two minutes, and keep captions/runtime disclosures
accurate. Publish to YouTube or Vimeo with visibility allowed by the
[submission requirements](SUBMISSION_REQUIREMENTS.md). Complete the remaining
entrant confirmations and product acceptance separately.

The previous 98-second review edit remains in
[its original EDL](demo/submission-candidate.edl.json); its footage predates the
final recovery fixes and is not the current submission candidate. Its review
history is preserved in Git and the earlier local evidence packages.
