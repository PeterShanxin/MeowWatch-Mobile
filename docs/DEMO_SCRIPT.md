# MeowWatch Mobile — submission film

The current edit is a **94-second hybrid product film**, combining frame-driven
React UI animation with actual Android recordings. The animation explains
interactions at a readable scale; real footage shows playback, fullscreen,
Continue Watching and RevenueCat Test Store behavior. It is an edited product
story, not a single uninterrupted session.

The continuous-shot visual revision uses a consistent
deep navy stage. The phone and tablet persist through connected camera
moves instead of alternating light/dark chapter cards. This is a presentation
treatment; it does not turn the edited captures into one recorded session.

The editable [Remotion project](../showcase/remotion/README.md) and
[storyboard](../showcase/remotion/STORYBOARD.md) contain the composition,
references and scene boundaries. The first four feature scenes were rebuilt
at the owner's request because the earlier emulator recordings looked choppy.
A 30 fps export cannot restore missing source frames. Recreated UI is therefore
explicitly labeled **UI animation · based on the app**; it is not synchronization
or purchase acceptance evidence.

## Story

| Film time | What the viewer sees | Presentation |
| --- | --- | --- |
| 0–3 | Movie night, even miles apart. | Kinetic brand typography |
| 3–11 | A tap starts a room and reveals an invitation action. | Animated app UI |
| 11–19 | A tablet enters the invitation and joins. | Animated app UI |
| 19–29 | Play, pause and seek affect both illustrated screens. | Animated app UI |
| 29–35 | A message appears for the other person. | Animated app UI |
| 35–45 | Sintel plays in Local Player Mode on a real phone. | Physical Android capture, 1× |
| 45–52 | Landscape fullscreen expands across the composition. | Physical Android capture, 1× |
| 52–62 | Continue Watching restores the saved position, paused. | Emulator capture, 1× |
| 62–66 | One free hosted session per local day; guests join free. | Editorial quota card |
| 66–72 | Native Test Store purchase and Plus activation. | Emulator capture, 1×, no charge |
| 72–76 | Restore on the same active customer. | Emulator capture, 1× |
| 76–80 | Glass Aurora appearance. | Emulator capture, 1× |
| 80–85 | A premium Movie night reaction. | Emulator capture, 1× |
| 85–90 | Another Plus session in Cinema Noir. | Emulator capture, 1× |
| 90–94 | Together. The Android counterpart to open-source MeowWatch. | Brand ending |

Nearby remains a secondary explicitly paired remote and is not a dedicated
film chapter. Automatic nearby room creation is outside the approved direction.
The film does not depict an unverified Cast receiver.

## Sources and runtime boundaries

- The recreated screens follow the actual Flutter UI, with interaction copy
  checked against the earlier phone/tablet journey. Decorative connections,
  tap pulses and illustrated progress do not claim measured network latency.
- Physical Local/fullscreen: OnePlus PLK110, Android 16 / API 36, ordinary
  `67d0206` Test Store APK. The reviewed app-only excerpts, exact intervals and
  Sintel credit are in [source media](../showcase/remotion/source-media/README.md).
  The phone encoded the original footage. These excerpts run at 1×.
- Continue Watching: [36103033022, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36103033022/attempts/2),
  normal release APK on an API 35 emulator. It restores 69 seconds after a new
  process and resumes only after explicit Play.
- Purchases and Plus: [36103033131](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36103033131),
  actual RevenueCat SDK/Test Store and native phone UI, with a headless TLS peer.
  The accepted journey includes cancellation, failure, success, clean-cache
  Restore, premium appearance/reaction and two distinct Plus hosts.
- Original emulator source intervals and receipts are retained in the
  [source edit](demo/submission-final.edl.json) and its
  [artifact record](demo/submission-final.edl.sources.json). Some older clips
  are now replaced by the labeled UI animation and are not in the final timeline.

The Bee fixture is CC0. Sintel is credited to Blender Foundation under CC BY 3.0.
DM Sans and DM Serif Display include their OFL notices. The music is an original
synthesized 120 BPM score. Reference studios' footage, music and proprietary
templates are not included. See [third-party notices](../THIRD_PARTY_NOTICES.md).

## Review and publication

TypeScript checks and a focused independent review pass; the review's misplaced
Join tap was corrected and inspected in Studio. Representative scene checks
also corrected text overlap. Hosted render
[36125298522](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36125298522)
exports the `7730515` hybrid edition at 1920 × 1080, 30 fps, 94.059 seconds.
Representative rendered scenes were inspected and browser playback reached
the ending at 1×. Technical audio checks found no clipping. The requested
continuous-shot revision passes TypeScript and representative Studio review,
including join, shared controls, fullscreen and purchase. It still needs its
own hosted export and final playback check before publication.

Run **Remotion submission film** to prepare the documented sources, generate the
score and export 1920 × 1080 H.264/AAC at 30 fps on hosted Ubuntu. The timeline
contains 2,820 frames; the encoded container can include a small audio tail.
Verify that the final duration is strictly below two minutes.

The earlier silent edit is saved on YouTube as a private review upload. It is
not the final video and cannot satisfy public submission availability. The
physical-footage Remotion edition `ec26bb8`, rendered by `36120725164`, is also
superseded by this hybrid direction. Keep the final runtime/source labels,
credits and public visibility consistent with [submission requirements](SUBMISSION_REQUIREMENTS.md).
Product acceptance and repository closeout remain tracked in [STATUS.md](STATUS.md).
