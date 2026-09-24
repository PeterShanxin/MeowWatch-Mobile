# MeowWatch Mobile — demo script

## Current edit: 104-second submission candidate

The [edit decision list](demo/submission-candidate.edl.json) and
[source pins](demo/submission-candidate.edl.sources.json) assemble fresh native
phone/tablet footage, Local resume, landscape fullscreen and RevenueCat Test
Store into one 1920 × 1080 film. It is a **review candidate**, not a published
submission or a claim that the remaining [acceptance gates](STATUS.md) are done.

The sources share the same app implementation: f16b148 and 9a4e29c differ in
the retained-composer integration-test helper, not app code. Together/purchase
use development runtimes; Local and fullscreen use normal release APKs.
These are distinct recorded journeys, not one uninterrupted take or one binary.

Rendering and strict decoding run on hosted CI. The development computer only
downloads the small review package and displays static original/output frames.
This avoids local Android emulators, builds and video transcoding during the
resource-constrained development session.

## Shot sequence and exact cuts

All native clips run at **1×**. Single-device intervals are seconds from the
source's first video PTS, written as [in, out). Paired intervals use the
shared approximate recording clock. Titles, captions and thin device frames
sit outside the complete original capture; no app pixels are covered or cropped.

| Output seconds | Source interval | Action and message |
| --- | --- | --- |
| 0–4 | Branded graphic | **Movie night, even miles apart.** |
| 4–12 | phone 13–21 | Room becomes ready; **Start a room. Invite someone in.** |
| 12–18 | Paired clock 24–30 | Guest joins the host's room. |
| 18–36 | Paired clock 41–59 | Two-way play, pause and seek. |
| 36–44 | Paired clock 59–67 | Chat messages and reactions beside the movie. |
| 44–58 | local 56–70 | Continue Watching at 0:56, restored pause and explicit Play. |
| 58–64 | fullscreen 10–16 | Actual phone landscape playback with controls hidden. |
| 64–69 | paywall 50–55 | Daily free-session limit and purchase entry. |
| 69–79 | purchase 8–18 | Native RevenueCat Test Store purchase and Plus activation. |
| 79–85 | purchase 19–25 | Same-active-customer Restore and appearance selection. |
| 85–93 | purchase 31–39 | Glass Aurora playback and Movie night reaction. |
| 93–99 | purchase 49–55 | A distinct second Plus room in Cinema Noir. |
| 99–104 | Branded graphic | Android, open source, AGPL-3.0-only and repository. |

## Pinned original sources

All source videos were recorded on **Android API 35 x86_64 emulators**.
Full commits, hashes, original paths and artifact names are machine-readable in
the EDL and source pins. The fetcher requires successful runs at those commits.

| Source | Native run | Commit | Original size |
| --- | --- | --- | --- |
| Phone and tablet | [36031293517](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36031293517) | 9a4e29cd27843feb645699e713b72adc8b74a830 | 432 × 960 / 960 × 600 |
| Local resume | [36029407933](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36029407933) | f16b148b963a3225ed514ffaf29705bc14a24235 | 432 × 960 |
| Phone fullscreen | [36029407579](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36029407579) | f16b148b963a3225ed514ffaf29705bc14a24235 | 960 × 432 |
| Paywall and purchase | [36029407726](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36029407726) | f16b148b963a3225ed514ffaf29705bc14a24235 | 480 × 1040 |

Fullscreen uses phone attempt 2; attempt 1 failed downloading an Android system
image before any app launch. The paired timing manifest is SHA-256
87793bf73589c80b62013eea57011303825b435c1a3fa3b283d82fe211d7ee32.
Its estimated phone start is 0.000271 seconds after the tablet. These ADB
command timestamps are approximate, not proof of frame synchronization. Neither
device is independently retimed to make the players appear closer.

The purchase originals have a **1.231-second recording gap**. Every selected
shot stays inside one source segment, with visible editorial cuts for omitted
actions and waits. The 30 fps export preserves source-held frames; it does not
invent smoother motion. Native Together recordings contain 1,407 phone and
1,386 tablet pictures across approximately 126 and 127 seconds respectively.

## Review evidence and boundaries

The first 106-second candidate rendered in
[36034311762](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36034311762),
with all 3,180 frames strictly decoded and 27 output samples retained. Review
found readable captions and complete device framing. It also showed the real
Plus activation and Movie night reaction that sparse source samples missed.
The next edit clarifies Test Store wording, removes repeated paired-runtime
copy, moves the start shot past most loading, and trims two seconds from Join.

The revised 104-second candidate renders successfully in
[36035397960](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/36035397960).
All 3,120 frames strictly decode and all 26 output samples have been inspected.
The independently recomputed video SHA-256 is
d6fab4dd025df6643143205c834a92c59314ecc5f0f1d9e658175035f69b2e03.
Captions and frames do not overlap the app. This review also exposes a tablet
video-stage clipping defect: the keyboard compresses the visible video, and
the reaction at the stage's lower edge is partly outside the scroll viewport.
That original footage is retained. The defect needs correction and fresh native
recording before this candidate can be accepted; editing must not conceal it.

- The Local excerpt includes the saved Continue Watching card and restored
  pause. Process termination/relaunch is established by the full native receipt,
  not this cut.
- Purchase is **RevenueCat Test Store, with no real charge**. It has one native
  Android player and an independent headless TLS peer. Restore keeps the same
  already-active customer; it does not show reinstall or lost-identity recovery.
- Together uses independently running emulators. App position checkpoints do
  not establish identical decoded frames, smooth source capture or physical
  hardware behavior. Full-film motion review remains a distinct acceptance step.
- The fullscreen frame is labelled **Phone / landscape**. The compositor's
  landscape layout token does not mean it was recorded on a tablet.
- Nearby and Cast footage awaits actual Android-to-Windows LAN and Cast receiver
  acceptance. Their absence from the film does not close product criteria.

## Reproduce the edit

Run the repository's **Check** workflow manually with
submission_edit=docs/demo/submission-candidate.edl.json. The hosted film job
fetches exact successful artifacts, verifies pins, renders the complete film,
strictly decodes it and retains four-second review images. No Android instance
starts in this rendering job. The resulting submission-film-review-1 artifact
includes the film, resolved EDL, source runs, output hash and manifest.

Use the navy, cream and blue cat/play identity and original-speed cuts. Keep
the runtime and Test Store labels. Never crop away faults, synthesize motion,
bridge a missing recording interval or pad an incomplete source with frozen
video. The film is silent. Added narration or music would require separate
rights and a new final duration check. The Bee fixture is CC0; the in-app Sintel
sample is CC BY 3.0, as detailed in [third-party notices](../THIRD_PARTY_NOTICES.md).

## Before publishing

- [ ] Accept remaining product and physical gates in STATUS; editing does not
  replace a clean-install rehearsal or legal confirmation.
- [ ] Retain originals, exact EDL, timing and input/output hashes.
- [ ] Watch the entire final export at normal speed: readable UI and captions,
  natural motion, no misleading claims or obscured actions.
- [ ] Confirm encoded duration below two minutes and publish an approved video
  using the [submission requirements](SUBMISSION_REQUIREMENTS.md).
- [ ] Keep the required 1179 × 2556 screenshot separate, original and unframed.

The earlier 118-second mixed-build Review Preview and 32-second hosted render
rehearsal are historical. Their receipts remain in the local evidence packages
and [acceptance history](ACCEPTANCE_HISTORY.md); neither is the current candidate.
