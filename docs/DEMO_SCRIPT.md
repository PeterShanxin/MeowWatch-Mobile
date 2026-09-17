# MeowWatch Mobile — 110-second demo script

> **Recording status (2026-09-17): review previews, not a final film.** The
> current purchase chapter is the **40.2-second v2**, using the original
> `9b7e9ed` recordings from
> [production purchase 35212468110](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468110).
> The later `300ca2e`
> [paired Together run 35230867493, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867493)
> passes and its drivers, native logs and 216.667-second paired evidence film
> have been independently audited. Those originals have not yet been selected
> into the final under-two-minute film. The same head's
> [five-layout journey 35230867480](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867480)
> passes all five complete drivers. These are Android emulator results.

## Capture and edit rules

- Target **110 seconds**, 1920 × 1080 at 30 fps; final duration must be under
  two minutes. Use the selected cat/play brand assets, navy background, cream
  captions and restrained blue accents.
- Use original native recording segments from accepted runs. The browser
  showcase and continuous development recording are separate deliverables.
- Fit each complete capture proportionally inside a simple device frame.
  Keep labels and captions outside app pixels: no crop, zoom, replacement UI,
  simulated motion or overlays inside the captured screen.
- Keep footage at **1× speed**. Use direct cuts for omitted waits and separate
  sessions. The default export is **silent with short captions**; narration is
  optional and must be genuinely recorded. No background music is required.
- Label emulator sources accurately, including **Phone · Host**, **Tablet ·
  Guest** and **Android emulators · approximate recording alignment · 1×**.
  Align paired segments using their shared schema-v2/v3 timing manifest; never
  move one device independently to make playback appear synchronized. A proof interval
  must be covered by both originals without a recording gap or segment boundary.
- Retain actual participant names, messages, dialogs and test choices. Use
  licensed demo media and avoid personal information. Do not replace visible
  test names with invented people or describe a protocol peer as a filmed device.

The [submission compositor](../tools/submission_demo/README.md) enforces the
supported framing and timing contract. Its manifest records source runs, full
commits, hashes and source ranges; human inspection still establishes whether
this footage and its claims are acceptable.

## Shot-by-shot plan

Times below are planned final output times; the allocation remains provisional
until the audited paired originals are selected and the complete film is
reviewed. Purchase source points match v2 below. Screenshots are state anchors,
not motion sources.

| Time | Actual footage | Short caption / optional narration | Acceptance boundary |
| --- | --- | --- | --- |
| **0:00–0:06** | Branded title card, optionally with a real home screenshot. | **MeowWatch Mobile** / **Movie night, even when you're miles apart.** | Identify the title as graphics and the screenshot as a still. |
| **0:06–0:19** | Phone taps **Start a room**; tablet enters its invite in **Join a room**. Hold both participant names. | “Start a room. Join from the invite. No account setup.” | `300ca2e` paired CI and independent artifact audit pass; final shot selection remains. The driver decodes an invitation image and types the result into the real sheet; this does not film camera QR scanning. |
| **0:19–0:39** | Paired native video: host Play, Pause and seek, followed by guest control and host response. | **Play · Pause · Seek** / **Either person can control** | Retain at least one continuous cause-and-response interval at 1×. Both decoded surfaces and accepted native convergence results are required; no invented drift counter. |
| **0:39–0:50** | Guest sends the actual movie-night chat, host receives and replies; guest sends a heart and host shows it. | “Chat and reactions keep the shared moment beside the movie.” | Both production UI social paths must pass. Preserve the recorded names and message text. |
| **0:50–1:01** | Separate Local Mode take: brief real playback, then Home → **Continue Watching** → saved video at its recorded position. | **Your place, remembered** / “Local Mode works when you just want a player.” | All five `300ca2e` layout drivers pass. The previously inspected `f8fdd62` Local take from [35191578190](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35191578190) retains its own provenance. Select and inspect the final take; restored video is paused, without implying autoplay or history from the preceding Together room. |
| **1:01–1:12** | `purchase-1`, **47.993–58.993**: free room playing → leave → quota paywall. | **Host more movie nights** / “Joining stays free. One hosted session a day is included.” | Keep the actual protocol-peer label in this pinned take; it has one Android player, not a filmed tablet. |
| **1:12–1:18.2** | `purchase-2`, **13.003–19.203**: native Test Store valid-purchase action → brief real active-entitlement heading. | **RevenueCat Test Store · sandbox purchase** / **Unlimited hosting with MeowWatch Plus** | The active heading lasts only 0.4667 seconds in this edit and still has a spinner. Do not call it a prolonged settled-success state. Retain cancellation/failure evidence separately. |
| **1:18.2–1:24.2** | `purchase-2`, **23.043–29.043**: Settings already active → restore result → Glass Aurora selected and saved. | **Plus is active** / **Restore, then choose Glass Aurora** | This explicit cut supplies the longer readable active-state confirmation. Restore retains the same already-active customer; it does not prove recovery after lost identity or reinstall. |
| **1:24.2–1:34.2** | `purchase-2`, **38.084–48.084**: first paid room plays in Glass Aurora → Movie night picker → clapperboard reaction echo. | **A little more movie-night magic** | Real paid-room playback and the premium reaction are visible; the accepted TLS peer receipt confirms delivery. No synthetic reaction overlay. |
| **1:34.2–1:41.2** | `purchase-3`, **0.000–7.000**: a distinct second paid room plays in Cinema Noir. | **Another room. Another movie night.** | Use an explicit cut into this separate take. Preserve the room identity and advancing player; do not imply uninterrupted setup across the segment gap. |
| **1:41.2–1:50** | Branded closing card. | **Watch together, wherever you are.** / **Android-first · Open source · AGPL-3.0-only** / **github.com/PeterShanxin/MeowWatch-Mobile** | Use the final public source URL. Do not claim submission readiness or physical-device testing in the film. |

Together and social selection can use the independently audited `300ca2e`
recording, with its real names and source details retained. The older
ANR-obscured `35212468221` footage remains unsuitable. Purchase shots total
**40.2 seconds** at 1×. Use clear editorial cuts between Together, Local and
purchase takes.

## Current purchase review preview

The local package `.local/deliverables/purchase-preview-9b7e9ed-v2/` contains
the MP4, exact EDL, hashes, source/renderer provenance and `review.md`. The
40.2-second file has 1,206 frames, a 1920 × 1080 canvas and no audio. Phone
content is 448 × 974 pixels, about 25% larger than v1, with 24px disclosures
outside the app pixels. A local copy of the compositor supplies this layout;
the shared repository compositor is unchanged. Full decoding and source-clock
correspondence checks completed, and 52 output time points across all five
shots were visually inspected. This is not continuous end-to-end viewing or
final-film acceptance. The old 43-second v1 remains historical.

The unchanged source has only 0.488444 seconds of clean active-entitlement
heading, starting at source PTS 18.734500; its spinner remains. At 19.222944,
the first enabled Done button coincides with anomalous red/yellow loading text
behind the sheet. There is no 2–3-second clean settled-success window to retain.
v2 ends that source at 19.203 and cuts to the later Settings confirmation;
it does not freeze or slow the successful state. Omitting the anomalous interval
from a preview does not resolve the underlying app appearance defect, whose
fix needs fresh native proof. A clean recapture is required for a longer
purchase-success hold. Test Store, same-customer restore and headless-peer
disclosures remain visible throughout their relevant shots.

Current billing acceptance is newer than this preview:
[300ca2e production purchase 35230867387, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867387)
passes 12 stages, one free and two paid hosts, real Test Store outcomes and
same-customer restore. Its
[relaunch/expiry run 35230867563](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867563)
also passes: the real purchase renews through 14:31:44Z, expires at 14:36:44Z,
and fresh SDK data at 14:36:55.873Z is inactive; restore at 14:36:56.001Z remains
inactive for the same customer. These are audited SDK receipts, not continuous
expiry-wait video. They do not replace the pinned `9b7e9ed` preview sources.

## Pinned purchase sources

All three sources are full-frame **720 × 1560** recordings from API 35
`sdk_gphone64_x86_64`, run `35212468110`, artifact directory
`production-purchase-1/production-purchase-artifacts/20260917T105737Z-6e753b05`.
Their full source commit is `9b7e9ed08d0d83487441678b0aaee342d690138f`.
Timecodes above are source PTS seconds; all selected durations are whole 30 fps
frame counts. Put these hashes and the downloaded original paths in the final
EDL; the tool's example EDL remains an unaccepted placeholder.

| Source ID | Original file | SHA-256 |
| --- | --- | --- |
| `purchase-1` | `journey-001.mp4` | `f29d5c22d7ded31b5f8f1e580d2a165ea4e325820c8a94c631f23db2d046ea54` |
| `purchase-2` | `journey-002.mp4` | `26a600d6a890cabb0fa52f23c0ec9970726049058dfd0dbcdfac99e3461b7e0d` |
| `purchase-3` | `journey-003.mp4` | `77396f3b468c5a0f1dd6bf2ae000be31e47757bb1f0baf6c35efe39f16c4d46c` |

Playable gaps between these files are approximately **3.384/2.623 seconds**,
distinct from the recorder's 1.281/1.705-second coverage gaps. They cross
cancellation/reopening and second-paid-room setup; neither is presented as a
continuous proof action. Keep all source segments and gap metadata. Stop the
third clip before its black/launcher teardown, which begins around PTS 8.7.

## Nearby and Cast

Neither feature is in the current 110-second cut. Nearby may enter a revised
edit only after actual Android-to-Windows discovery, explicit pairing and
playback control pass with the companion build available. Cast requires actual
receiver playback proof. A picker, same-device transport probe or Windows-only
test does not satisfy either gate. Omitting footage does not close the product's
outstanding acceptance criteria.

## Final recording acceptance

- [ ] Accepted production create/join, two-way playback control, chat and
  reaction footage shows both independent Android runtimes.
- [ ] Continue Watching visibly restores real saved progress; all chosen
  footage names its actual accepted build and runtime.
- [ ] One accepted purchase journey proves quota, native Test Store success,
  entitlement and two distinct paid sessions. Restore copy matches its scope.
- [ ] Original segments, timing manifests, source hashes and the authored edit
  decision list are retained; every paired proof interval has full coverage.
- [ ] Final export is watched end-to-end, readable, under two minutes and free
  of misleading runtime or purchase claims. Any narration and media are cleared.
- [ ] The required 1179 × 2556 submission screenshot is an original unframed
  native PNG, not an extracted or upscaled frame from the 1080p film.
