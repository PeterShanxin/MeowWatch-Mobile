# MeowWatch Mobile — demo script

## Current edit: 118-second Review Preview

The current edit combines accepted **5137e58 Together** recordings with
**2fc38317 Local and purchase** recordings. It is a mixed-build review preview,
not the final submission film or a complete product rehearsal. The paired
footage still has visibly sparse motion; exporting at 30 fps repeats the
original held frames rather than improving the native motion.

[STATUS.md](STATUS.md) owns current acceptance results and remaining gates,
including the latest Range experiment and fullscreen checks. A newer passing
workflow does not change this edit's source build or approve its picture quality.

The local review package is `.local/deliverables/demo-5137e58/`:

- Video: `MeowWatch-Mobile-Review-Preview-118s-v1.mp4`.
- SHA-256: `731806b6778c5a897430db0bc90cd08b2ea69ac926dcc530eb68ef84b4de119c`.
- Edit decision list: `meowwatch-mobile.edl.json`.
- Source and review receipts: `source-provenance.json`,
  `review-verification.json`, and the video's `.manifest.json`.

The 1920 × 1080 export is exactly 118 seconds. All 3,540 frames decode and all
11 pinned inputs match their hashes. Inspection covered 29 output samples and
six full-resolution images; these checks do not replace final end-to-end viewing.
The local package is not a published submission video.

## Shot sequence and exact cuts

All native clips run at **1×**. Single-device intervals are seconds from the
source's first video PTS, written as `[in, out)`. Paired intervals use the one
shared recording clock described below. Titles and captions sit outside the
complete device capture.

| Output seconds | Source interval | Action and on-screen message |
| --- | --- | --- |
| 0–6 | Branded graphic | **Movie night, even miles apart.** / Watch together. Stay close. |
| 6–10 | `together-phone-000` 28–32 | Original onboarding tail, Home and Start. **Start a movie night.** |
| 10–17 | Paired clock 45–52 | Guest reviews the real invite and joins. **An invite brings you into the same room.** |
| 17–58 | Paired clock 67.5–108.5 | Continuous two-device controls, chat and heart. **Shared controls. A chat. A heart.** |
| 58–69 | `local-lifecycle-2` 87–98 | Already-restored pause at 1:13, explicit Play, progress to 1:20. **Your place, remembered.** |
| 69–79.8 | `purchase-1` 54.8–65.6 | Paywall and native Test Store cancellation. **Cancelling keeps you free.** |
| 79.8–90.6 | `purchase-2` 3.7–14.5 | Failure feedback, retry and native success. **Retry the test purchase and unlock MeowWatch Plus.** |
| 90.6–98.4 | `purchase-2` 18.2–26 | Same-active-customer Restore and appearance selection. **Restore your purchase. Make the player yours.** |
| 98.4–105 | `purchase-2` 38.6–45.2 | Glass Aurora playback and Movie night reaction. **A reaction worth sharing.** |
| 105–111 | `purchase-3` 4.5–10.5 | A distinct second paid room in Cinema Noir. **Another room. More movie night.** |
| 111–118 | Branded graphic | **Watch together, wherever you are.** / Android-first · Open source · AGPL-3.0-only · github.com/PeterShanxin/MeowWatch-Mobile |

Keep **Review Preview** visible until final acceptance. The purchase chapter is
42 seconds within this edit, not a separate final film.

## Pinned original sources

The following are original native recordings, not framed intermediate previews.
All were captured on **Android API 35 x86_64 emulators**.

- Together: [run 35243162891](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35243162891),
  commit `5137e5870f9ac611a339daf42bcd24abfcbb412d`, artifact
  `production-phone-tablet-1`, session `20260917T160245Z-9679`.
- Local: [run 35236920517](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920517),
  commit `2fc38317f96efa2b15239b6be3dfedce9264987c`, normal release lifecycle,
  artifact `android-native-lifecycle-1`, path
  `android-lifecycle-artifacts/native/lifecycle-02.mp4`.
- Purchase: [run 35236920484](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920484),
  attempt 1, the same `2fc38317` commit, artifact `production-purchase-1`, path
  `production-purchase-artifacts/20260917T150501Z-d66f50ff/`.

| Source ID | Original file | Capture size | SHA-256 |
| --- | --- | --- | --- |
| `together-phone-000` | `phone-000.mp4` | 720 × 1600 | `90953302fba98392dec4384df047250fec20b1f9580321d6a18388272760825a` |
| `together-tablet-000` | `tablet-000.mp4` | 1280 × 800 | `9f1d2795a13ba8ff64674706673439b658d2875a795019818a705f7a39ab08ea` |
| `local-lifecycle-2` | `lifecycle-02.mp4` | 432 × 960 | `ce64f2b55dc1c888a04cca9c8a7a88e005e504b4d96eed51977d62c7b81efaf1` |
| `purchase-1` | `journey-001.mp4` | 480 × 1040 | `99b4835bcf44cb9895cc481708525c32ee9cf3fba8b21de9896ea414228bf638` |
| `purchase-2` | `journey-002.mp4` | 480 × 1040 | `0ee714253249f18fb6cfa6e5a9bc42bbd6ea9df2a35223b7b120b8dce1e4a311` |
| `purchase-3` | `journey-003.mp4` | 480 × 1040 | `47a8f5e1efd73d7bab74d2c45316a66e1e10ff76f37ac5c5e127003bfdc2a311` |

The paired timing source is the same Together session's
`meowwatch-two-device.mp4.manifest.json`, SHA-256
`c13002f2604ec456138169f372b86fed8663b47e9f980b618ae5885edea53376`.
The tablet starts **0.017622 seconds** after the phone on that estimated clock;
both selected paired windows have complete source coverage. ADB timestamps
provide approximate alignment, not frame synchronization. Never independently
retime one device to make the players appear closer.

The purchase originals have **1.068- and 0.738-second recording gaps**. Selected
shots stay inside individual segments, using visible editorial cuts for omitted
actions and waits. Preserve the timing receipts; host command time and video
PTS are different clocks.

## What the edit can and cannot show

- The Local shot begins after history restoration. Home, process restart and
  history selection are outside the cut; their acceptance comes from the full
  lifecycle evidence, not these eleven seconds.
- The failed-purchase button tap precedes its selected excerpt. The success
  heading is brief and initially loading; a clear cut leads to the readable
  Settings confirmation. Do not freeze or extend a successful state.
- Purchase footage uses **one native Android player and an independent headless
  TLS peer**. Label it **RevenueCat Test Store · no real charge**. Restore retains
  the **same already-active customer**; it does not demonstrate reinstall,
  lost-identity recovery, process relaunch or expiration.
- The phone and tablet are independently running emulators. Neither the edit
  nor its source runs establish physical hardware behavior. The tablet's native
  viewport partially clips the heart reaction; retain the original pixels and
  resolve picture quality before accepting the final film.
- Nearby and Cast are absent from this cut. Add them only after actual
  Android-to-Windows discovery, pairing and control, or actual Cast receiver
  playback, respectively. Omitting footage does not close their product criteria.

## Capture and render the final revision

1. Choose the accepted app build and record its full commit, runtime and checks
   from [STATUS.md](STATUS.md). Rehearse from a clean install. Use two independent
   devices for Together and media that both participants are entitled to play.
2. Capture room creation, invitation review, two-way control, chat and reactions.
   Retain readable controls and the real response on both devices. For Local,
   capture the saved position and explicit Play; include history selection if
   the final caption claims to show it.
3. Capture the real RevenueCat Test Store paywall, cancellation, retry, purchase,
   Restore and paid benefits. Keep the actual SDK dialogs, customer scope and
   peer type visible. Keep separate sessions and recording gaps as honest cuts.
4. Copy the accepted originals and timing receipts into the edit package. Pin
   every source's hash, dimensions, runtime, run and full commit in a new EDL.
   Use the table above as the current sequence, replacing shots only with
   inspected footage and updating their cuts and provenance together.
5. Render with the [submission compositor](../tools/submission_demo/README.md):

   ```powershell
   python tools/submission_demo/compose.py inspect path/to/original.mp4
   python tools/submission_demo/compose.py validate path/to/final.edl.json
   python tools/submission_demo/compose.py render path/to/final.edl.json path/to/meowwatch-mobile-final.mp4
   ```

Use the navy, cream and blue cat/play identity, complete phone/tablet frames and
short captions. Preserve 1× playback, source-held frames and app pixels; do not
crop away faults, synthesize motion or pad a short source with frozen video.
Paired labels are **Phone · Host** and **Tablet · Guest**, with
**Android emulators · approximate recording alignment · 1×**. Use the real
runtime if new footage differs. The current edit is silent; any narration or
music added later needs its own rights and final duration check. Retain licensed
media attribution, including the Blender Foundation Sintel sample, as recorded
in [third-party notices](../THIRD_PARTY_NOTICES.md).

## Before publishing

- [ ] Current product gates and full clean-install rehearsal are accepted in
  STATUS; unresolved physical or legal requirements are not hidden by editing.
- [ ] All selected clips show real actions and responses on their named build
  and runtime. Paired proof windows have uninterrupted coverage on both sources.
- [ ] Source recordings, timing manifests, exact EDL and input/output hashes are
  retained. No recording gap is presented as continuous behavior.
- [ ] Watch the entire final export at normal speed: readable UI and captions,
  natural motion, no OS dialogs obscuring the app, and no misleading claims.
- [ ] Final encoded duration is strictly below two minutes; publish the approved
  video using the [submission requirements](SUBMISSION_REQUIREMENTS.md).
- [ ] The required 1179 × 2556 screenshot is a separate original, unframed native
  PNG, not a resized or extracted frame from the 1080p film.
