# MeowWatch Mobile — 110-second demo script

> **Recording status (2026-09-17): final acceptance pending.** At `9b7e9ed`,
> [production purchase 35212468110](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468110)
> passes all 12 stages; its critical screenshots and reviewed raw footage have
> no unexpected system modal. The current
> [product journey 35212468253](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468253)
> passes phone, portrait tablet, landscape tablet and landscape phone; small
> phone completes all 20 app steps but fails teardown. These are API 35 emulator
> results. [Together 35212468221](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468221)
> has an app ANR obscuring its phone recording and does not pass. It cannot
> supply the paired shots below; fresh production acceptance and the final film
> remain open.

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
  Align paired segments using their shared schema-v2 timeline; never move one
  device independently to make playback appear synchronized. A proof interval
  must be covered by both originals without a recording gap or segment boundary.
- Retain actual participant names, messages, dialogs and test choices. Use
  licensed demo media and avoid personal information. Do not replace visible
  test names with invented people or describe a protocol peer as a filmed device.

The [submission compositor](../tools/submission_demo/README.md) enforces the
supported framing and timing contract. Its manifest records source runs, full
commits, hashes and source ranges; human inspection still establishes whether
this footage and its claims are acceptable.

## Shot-by-shot plan

Times below are final output times. Purchase source points are pinned below;
the paired shots still need accepted originals. Screenshots are state anchors,
not motion sources.

| Time | Actual footage | Short caption / optional narration | Acceptance boundary |
| --- | --- | --- | --- |
| **0:00–0:06** | Branded title card, optionally with a real home screenshot. | **MeowWatch Mobile** / **Movie night, even when you're miles apart.** | Identify the title as graphics and the screenshot as a still. |
| **0:06–0:19** | Phone taps **Start a room**; tablet enters its invite in **Join a room**. Hold both participant names. | “Start a room. Join from the invite. No account setup.” | Await a clean passing two-device production take. The driver decodes an invitation image and types the result into the real sheet; this does not film camera QR scanning. |
| **0:19–0:39** | Paired native video: host Play, Pause and seek, followed by guest control and host response. | **Play · Pause · Seek** / **Either person can control** | Retain at least one continuous cause-and-response interval at 1×. Both decoded surfaces and accepted native convergence results are required; no invented drift counter. |
| **0:39–0:50** | Guest sends the actual movie-night chat, host receives and replies; guest sends a heart and host shows it. | “Chat and reactions keep the shared moment beside the movie.” | Both production UI social paths must pass. Preserve the recorded names and message text. |
| **0:50–1:01** | Separate Local Mode take: brief real playback, then Home → **Continue Watching** → saved video at its recorded position. | **Your place, remembered** / “Local Mode works when you just want a player.” | Four current layouts pass. The previously inspected `f8fdd62` Local take from [35191578190](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35191578190) remains usable with its own provenance. Restored video is paused; do not imply autoplay or history from the preceding Together room. |
| **1:01–1:12** | `purchase-1`, **47.993–58.993**: free room playing → leave → quota paywall. | **Host more movie nights** / “Joining stays free. One hosted session a day is included.” | This fresh free-host footage is clean. Keep the actual protocol-peer label; this take has one Android player, not a filmed tablet. |
| **1:12–1:21** | `purchase-2`, **10.003–19.003**: native Test Store valid-purchase action → Plus/hosting unlock. | **RevenueCat Test Store · sandbox purchase** / **Unlimited hosting with MeowWatch Plus** | A self-contained success attempt after earlier cancellation/failure. Keep the real dialog readable; retain the other outcomes in the evidence package. |
| **1:21–1:27** | `purchase-2`, **23.043–29.043**: Settings restore result → Glass Aurora selected and saved. | **Restore your purchase. Set the mood.** | Restore retains the same already-active customer. It does not prove recovery after lost identity or reinstall. |
| **1:27–1:37** | `purchase-2`, **38.084–48.084**: first paid room plays in Glass Aurora → Movie night picker → clapperboard reaction echo. | **A little more movie-night magic** | Real paid-room playback and the premium reaction are visible; the accepted TLS peer receipt confirms delivery. No synthetic reaction overlay. |
| **1:37–1:44** | `purchase-3`, **0.000–7.000**: a distinct second paid room plays in Cinema Noir. | **Another room. Another movie night.** | Use an explicit cut into this separate take. Preserve the room identity and advancing player; do not imply uninterrupted setup across the segment gap. |
| **1:44–1:50** | Branded closing card. | **Watch together, wherever you are.** / **Android-first · Open source · AGPL-3.0-only** / **github.com/PeterShanxin/MeowWatch-Mobile** | Use the final public source URL. Do not claim submission readiness or physical-device testing in the film. |

Together and social shots remain pending until their full native journey
passes and its originals are visually inspected. The ANR-obscured `35212468221`
recordings must not fill these slots, even where Flutter screenshots look clean.
Purchase shots total 43 seconds and retain all footage at 1×; inspect the final
framed edit for readability before accepting it. Use clear editorial cuts
between Together, Local and purchase takes.

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
