# MeowWatch Mobile — 110-second demo script

> **Recording status (2026-09-17): review previews, not a final film.** The
> current purchase chapter is the **42-second preview**, using the original
> `2fc3831` recordings from
> [production purchase 35236920484](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920484).
> The earlier `300ca2e`
> [paired Together run 35230867493, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867493)
> passes and its drivers, native logs and 216.667-second paired evidence film
> have been independently audited. Those originals have not yet been selected
> into the final under-two-minute film. The newer `2fc3831`
> [five-layout journey 35236920763](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920763)
> passes all five complete drivers, including compact-guide and modal-transition
> checks. Production purchase also passes with the corrected loading overlay.
> These are Android emulator results. New paired playback and expiry/restore
> follow-up remain open; consult [the current ledger](STATUS.md).

The first 61 seconds remain a provisional Together/Local selection. The later
pause fix at `6c44` passes 704 local app tests and the debug APK build;
[runtime matrix 35241701885](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35241701885)
awaits native proof. The `9e032ba`
[RevenueCat diagnostic run 35240675074](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35240675074)
has no accepted result recorded here. Neither pending run supplies final footage.

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
reviewed. Purchase source points match the 42-second preview below. Screenshots are state anchors,
not motion sources.

| Time | Actual footage | Short caption / optional narration | Acceptance boundary |
| --- | --- | --- | --- |
| **0:00–0:06** | Branded title card, optionally with a real home screenshot. | **MeowWatch Mobile** / **Movie night, even when you're miles apart.** | Identify the title as graphics and the screenshot as a still. |
| **0:06–0:19** | Phone taps **Start a room**; tablet enters its invite in **Join a room**. Hold both participant names. | “Start a room. Join from the invite. No account setup.” | `300ca2e` paired CI and independent artifact audit pass; final shot selection remains. The driver decodes an invitation image and types the result into the real sheet; this does not film camera QR scanning. |
| **0:19–0:39** | Paired native video: host Play, Pause and seek, followed by guest control and host response. | **Play · Pause · Seek** / **Either person can control** | Retain at least one continuous cause-and-response interval at 1×. Both decoded surfaces and accepted native convergence results are required; no invented drift counter. |
| **0:39–0:50** | Guest sends the actual movie-night chat, host receives and replies; guest sends a heart and host shows it. | “Chat and reactions keep the shared moment beside the movie.” | Both production UI social paths must pass. Preserve the recorded names and message text. |
| **0:50–1:01** | Separate Local Mode take: brief real playback, then Home → **Continue Watching** → saved video at its recorded position. | **Your place, remembered** / “Local Mode works when you just want a player.” | All five `2fc3831` layout drivers pass. The previously inspected `f8fdd62` Local take from [35191578190](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35191578190) retains its own provenance. Select and inspect the final take; restored video is paused, without implying autoplay or history from the preceding Together room. |
| **1:01–1:11.8** | `purchase-1`, **54.8–65.6**: production paywall → native Test Store dialog → Cancel and cancellation result. | **More movie nights** / “Plus adds unlimited hosting. Cancelling keeps you free.” | One native Android player plus a headless TLS peer. The original run proves the consumed free host; this selected shot starts at the paywall. |
| **1:11.8–1:22.6** | `purchase-2`, **3.7–14.5**: failed-purchase message → retry → native valid purchase → brief active Plus page. | **Make room for movie night** / “Retry the test purchase and unlock MeowWatch Plus.” | Disclose **RevenueCat Test Store · no real charge**. The failed-purchase button tap is outside the cut. The active heading occupies 1.0 second, initially with a spinner; enabled Done occupies only 7/30 second. |
| **1:22.6–1:30.4** | `purchase-2`, **18.2–26.0**: Settings → Restore → active confirmation → Glass Aurora selected and saved. | **Your Plus, still here** / “Restore the same customer, then choose Glass Aurora.” | A longer readable active-state confirmation. Cache-invalidated restore retains the same already-active customer; it does not prove lost-identity or reinstall recovery. |
| **1:30.4–1:37** | `purchase-2`, **38.6–45.2**: first paid room plays in Glass Aurora → Movie night picker → clapperboard reaction. | **A reaction worth sharing** / “Glass Aurora, real playback and a Movie night reaction.” | The accepted TLS peer receipt confirms delivery. Keep the original reaction and technical participant labels. |
| **1:37–1:43** | `purchase-3`, **4.5–10.5**: a distinct second paid room in Cinema Noir → Play and continuing video. | **Another room. More movie night.** / “A second paid room, with Cinema Noir.” | Direct cut into a later native segment; retain the room identity and advancing player without implying continuous setup. |
| **1:43–1:50** | Seven-second branded closing card. | **Watch together, wherever you are.** / **Android-first · Open source · AGPL-3.0-only** / **github.com/PeterShanxin/MeowWatch-Mobile** | Use the final public source URL. Do not claim submission readiness or physical-device testing in the film. |

Together and social selection can use the independently audited `300ca2e`
recording, with its real names and source details retained. The older
ANR-obscured `35212468221` footage remains unsuitable. Purchase shots total
**42 seconds** at 1×: 10.8 + 10.8 + 7.8 + 6.6 + 6.0. Together/Local uses the
first provisional 61 seconds, purchase ends at 103 seconds, and the seven-second
closing ends at **110 seconds**, strictly under two minutes. Use clear editorial
cuts between Together, Local and purchase takes.

## Current purchase review preview

The local package `.local/deliverables/purchase-preview-2fc3831/` contains
`MeowWatch-Purchase-Review-Preview-42s.mp4`, the exact
`purchase-review-preview-42s.edl.json`, renderer manifest, hashes,
`preview-provenance.json` and `review.md`. The film's SHA-256 is
`b0cdadd718b5782e99af65ee1fb4ff18b43dcee6bfeff6140a0bc0198263a50d`.
It has 1,260 frames, a 1920 × 1080 / 30 fps canvas and no audio. The unmodified
repository compositor fits complete phone content into a 450 × 975 area
(rounded content 450 × 974); 24px disclosures remain outside app pixels.

Full sequential decoding and pinned-input hash checks pass. All 1,260 output
phone frames were compared against the original held frame at their 1× source
clock; this scaled, lossy correspondence check is not pixel identity. Visual
review covered 53 output samples across every second and cut boundary, plus six
full-resolution images. A Codex browser playback spot-check inspected the actual
Restore/active screen. The whole 42 seconds has **not** been watched continuously,
and this preview does not establish final-film acceptance.

In the new original, the active heading runs from source PTS 13.471111 to
14.500333 (1.029222 seconds), initially with a spinner. Enabled Done starts at
14.264567 and lasts 0.235766 seconds. The selected cut retains 1.0 second of the
heading and 7/30 second of Done, then uses genuine Settings confirmation. It
does not freeze or slow the successful state. Cozy and Glass Aurora loading-text
corrections have fresh proof in this `2fc3831` source. Test Store, same-customer
restore and headless-peer disclosures remain visible in their relevant shots.

This preview's [2fc3831 purchase run](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920484)
passes 12 stages, one free and two paid hosts, real Test Store outcomes and
same-customer restore, with 98.8717% recording coverage. The separate `2fc3831`
expiry gate fails: active Restore follows an inactive sample, with insufficient
retained post-restore data to establish the cause. Its `9e032ba` diagnostic run
has no accepted result yet. Neither expiry nor process-relaunch footage appears
in this purchase chapter.

For historical context, the older `300ca2e`
[relaunch/expiry run 35230867563](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867563)
passes: the real purchase renews through 14:31:44Z, expires at 14:36:44Z,
and fresh SDK data at 14:36:55.873Z is inactive; restore at 14:36:56.001Z remains
inactive for the same customer. Those audited SDK receipts are not continuous
expiry-wait video and do not replace the newer failed gate.

The earlier 43-second v1 and 40.2-second v2 remain historical previews from
`9b7e9ed`, [purchase run 35212468110](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468110).
The v2 package at `.local/deliverables/purchase-preview-9b7e9ed-v2/` preserves its
own EDL and checks. It avoided an old loading-text defect and showed a shorter
active heading; neither its source ranges nor its acceptance are assigned to
the current 42-second chapter.

## Pinned purchase sources

All three sources are full-frame **480 × 1040** recordings from API 35
`sdk_gphone64_x86_64`, run `35236920484`, attempt 1, artifact directory
`production-purchase-1/production-purchase-artifacts/20260917T150501Z-d66f50ff`.
Their full source commit is `2fc38317f96efa2b15239b6be3dfedce9264987c`.
Timecodes above are source PTS seconds; all selected durations are whole 30 fps
frame counts. Put these hashes and the downloaded original paths in the final
EDL; the tool's example EDL remains an unaccepted placeholder.

| Source ID | Original file | SHA-256 |
| --- | --- | --- |
| `purchase-1` | `journey-001.mp4` | `99b4835bcf44cb9895cc481708525c32ee9cf3fba8b21de9896ea414228bf638` |
| `purchase-2` | `journey-002.mp4` | `0ee714253249f18fb6cfa6e5a9bc42bbd6ea9df2a35223b7b120b8dce1e4a311` |
| `purchase-3` | `journey-003.mp4` | `47a8f5e1efd73d7bab74d2c45316a66e1e10ff76f37ac5c5e127003bfdc2a311` |

The recorder reports **1.068/0.738-second** gaps between segments. Keep those
original timing records; source PTS and host command times are distinct clocks.
The five selected ranges remain inside individual original files and use direct
cuts for omitted actions and waits. They do not bridge either gap as a continuous
proof action. The selected third range ends at PTS 10.5, before black teardown.

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
