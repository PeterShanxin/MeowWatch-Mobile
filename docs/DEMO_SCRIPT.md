# MeowWatch Mobile — 110-second demo script

> **Recording status (2026-09-17): final acceptance pending.** The Local Mode
> and Continue Watching journey passes across five native API 35 emulator
> viewports at `f8fdd62` in [run 35191578190](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35191578190).
> Production purchase passes all ten stages at `70575be` in
> [run 35199455085](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455085).
> Its free-host raw interval is obscured by Google SDK setup's ANR; later clean
> quota, purchase, restore and paid-host clips have been identified separately.
> Final production Together acceptance and the edited film remain pending.

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

Times below are final output times. Locate source in/out points in the original
MP4s after acceptance; screenshots are state anchors, not motion sources.

| Time | Actual footage | Short caption / optional narration | Acceptance boundary |
| --- | --- | --- | --- |
| **0:00–0:06** | Branded title card, optionally with a real home screenshot. | **MeowWatch Mobile** / **Movie night, even when you're miles apart.** | Identify the title as graphics and the screenshot as a still. |
| **0:06–0:19** | Phone taps **Start a room**; tablet enters its invite in **Join a room**. Hold both participant names. | “Start a room. Join from the invite. No account setup.” | Production UI on two independent Android runtimes must pass. The driver transfers the invite and types it into the real sheet; this does not film sharing or QR scanning. |
| **0:19–0:39** | Paired native video: host Play, Pause and seek, followed by guest control and host response. | **Play · Pause · Seek** / **Either person can control** | Retain at least one continuous cause-and-response interval at 1×. Both decoded surfaces and accepted native convergence results are required; no invented drift counter. |
| **0:39–0:50** | Guest sends the actual movie-night chat, host receives and replies; guest sends a heart and host shows it. | “Chat and reactions keep the shared moment beside the movie.” | Both production UI social paths must pass. Preserve the recorded names and message text. |
| **0:50–1:01** | Separate Local Mode take: brief real playback, then Home → **Continue Watching** → saved video at its recorded position. | **Your place, remembered** / “Local Mode works when you just want a player.” | The `f8fdd62` native journey passes. Its restored video is paused; do not imply automatic playback or that this local history belongs to the preceding Together room. |
| **1:01–1:09** | Clean quota-paywall interval after the native cancellation result. | **Host more movie nights** / “Joining stays free. One hosted session a day is included.” | The accepted session ledger proves the free session was consumed; its moving free-host footage is obscured and must not be presented as clean. Use this same accepted run for the following Plus shots. Its headless TLS peer is not a filmed device. |
| **1:09–1:23** | Monthly purchase CTA → native RevenueCat Test Store success dialog → real success action → paywall closes and hosting unlocks. | **RevenueCat Test Store · sandbox purchase** / “MeowWatch Plus unlocks unlimited hosting.” | Keep the actual dialog readable for at least three seconds. Select the success attempt after cancellation/failure; retain those earlier outcomes in the evidence package. A recording gap through the proof action requires a new take. |
| **1:23–1:36** | First paid room playing → leave → start again → second distinct paid room playing. | **Another room. And another.** | Show both room identities and native progress. The accepted session ledger must prove two distinct paid Together Sessions; an empty automatically retried room is not a metered session. |
| **1:36–1:44** | Clearly cut Settings insert: **Restore purchases** → active Plus result → Appearance → **Cinema Noir** applied. | “Restore checks your purchase. Plus also sets the mood with Cinema Noir.” | These earlier shots are editorially reordered. Restore checks an already-active customer; it does not prove recovery after lost access or reinstall. If unreadable in eight seconds, hold the theme and retain restore in the evidence package. |
| **1:44–1:50** | Branded closing card. | **Watch together, wherever you are.** / **Android-first · Open source · AGPL-3.0-only** / **github.com/PeterShanxin/MeowWatch-Mobile** | Use the final public source URL. Do not claim submission readiness or physical-device testing in the film. |

Together and social shots remain pending until their full native journey
passes and the original recordings are visually inspected. The accepted
purchase run provides original quota, purchase, restore, theme and paid-hosting
footage; the selected cut still needs end-to-end review. A diagnostic harness
or a partial failed run cannot fill a missing production shot. Record source
changes between the Together, Local and purchase takes as clear editorial cuts.

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
