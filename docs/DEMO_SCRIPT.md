# MeowWatch Mobile — 110-second demo script

> **Recording status (2026-09-16): pending final acceptance.** This is the
> intended edit, not evidence that every shot has been captured. Record only
> actual product behavior from the final accepted build. Omit any conditional
> section that does not pass its stated gate.

## Capture and edit rules

- Final encoded duration target: **1:50 (110 seconds)**; hard limit is under
  2:00.
- Use actual phone and tablet recordings aligned to their real start times.
  Present them in simple, consistent device frames on a neutral background.
- Keep honest labels such as **Phone — Host** and **Tablet — Guest**. Do not
  imply physical-device testing when footage comes from Android emulators.
- Use clean voiceover and restrained app sound only. Use **no background music**.
- Use only owned, public-domain, or explicitly licensed demo media. Avoid
  third-party service logos, recognizable commercial footage, notifications,
  personal data, and test protocol messages.
- Record at readable scale. Prefer direct cuts and short matched zooms; avoid
  decorative transitions that hide whether the two devices agree.

## Shot-by-shot plan

| Time | Picture | Voiceover / on-screen copy | Evidence gate |
| --- | --- | --- | --- |
| **0:00–0:07** | Title over a clean split view of the MeowWatch home screen on phone and tablet. | **VO:** “Long-distance movie night should not begin with ‘three, two, one, play.’” **Text:** “MeowWatch Mobile” / “Movie night, even when you're miles apart.” | Home UI is implemented and native layouts have passed five AVD viewports. Final title capture pending. |
| **0:07–0:20** | Phone taps **Start a room**. Tablet taps **Join a room**, pastes the real invite, and both show each other's names. Keep both device frames visible. | **VO:** “Start a room on one Android device, share the invite, and join from another—no account setup.” | **Pending acceptance and recording:** production UI room creation, invite transfer, join, and roster on two independent Android runtimes. Do not use a harness-only screen. |
| **0:20–0:45** | Host loads an approved short video. Show both real video surfaces. Host presses play, pauses, then seeks; use one unobtrusive position callout after each action so the matching states are visible. | **VO:** “MeowWatch coordinates play, pause, and seek through the room, so both viewers stay together without a countdown.” | Core two-AVD native play/pause/seek passed. Complete production UI footage is still pending. Record the real decoded video surfaces and retain the accepted convergence report. |
| **0:45–0:58** | Tablet opens chat and sends “Ready for movie night! 🍿”. Phone shows the message. Tablet sends a heart reaction; phone shows the reaction over the player. | **VO:** “Chat, presence, and lightweight reactions keep the shared moment beside the movie.” | **Pending dual-Android production acceptance:** chat UI exists and protocol social signals pass, but the final production UI evidence is not yet complete. Show only intentional user-facing messages. |
| **0:58–1:08** | Leave the room or return home. Show the real **Continue Watching** card with title, progress, and time; tap it and resume near the saved position. | **VO:** “Stop when life interrupts. Continue Watching remembers your place, and Local Mode still works when you just want a player.” | Native Continue Watching and local direct-URL playback have passed across five AVD viewports. Final clean-install rehearsal and selected recording take are pending. |
| **1:08–1:29** | Start today's second hosted session as a Free user. Show the real Plus paywall and RevenueCat Test Store purchase. Return to the product, visibly show Plus, then start the new hosted session. | **VO:** “The core experience stays free. One hosted session a day is included, and RevenueCat powers MeowWatch Plus for unlimited hosting. Purchase and restore update the entitlement inside the app.” | **Pending integrated acceptance:** Test Store offering, cancel, failure, purchase, entitlement refresh, and restore pass on an AVD. The second-host paywall → purchase → immediate hosted-session unlock must pass as one production journey before recording. Label Test Store footage as a sandbox purchase; do not imply a Play Store charge. |
| **1:29–1:43** | Conditional: phone opens playback targets, discovers the actual Windows MeowWatch desktop, completes explicit pairing, then pauses or seeks the desktop video. Show phone and desktop only for this shot; return to phone/tablet framing afterward. | **VO:** “On the same network, the phone can also pair explicitly with MeowWatch on desktop and become a secure companion controller.” | **Conditional, pending physical proof:** protocol, protected storage, Android same-device transport, and Windows probes pass; Android-to-Windows LAN pairing/control remains unverified. Cut this entire shot unless physical cross-device acceptance passes and the desktop change is available for the submission. |
| **1:43–1:50** | Return to a clean phone/tablet synchronized playback hero shot, then logo and repository URL. | **VO:** “MeowWatch Mobile—watch together, wherever you are.” **Text:** “Android-first · Open source · AGPL-3.0-only” | Final accepted build, public repository URL, and closing capture pending. |

## Timing fallback if Nearby is not accepted

Remove **1:29–1:43** completely. Use six seconds to hold the verified
RevenueCat entitlement result, five seconds for a clearer Continue Watching
resume, and three seconds for the closing card. The result remains about 1:50
and makes no Nearby hardware claim.

## Cast rule

Cast is **not in the current 110-second cut** because hardware behavior is
unverified. If, and only if, final Cast hardware acceptance passes, replace up
to six seconds of another accepted feature with one continuous shot showing the
real target selection and synchronized Cast state. Do not extend the video and
do not show a target picker as proof that playback worked.

## Recording acceptance checklist

- [ ] One clean, uninterrupted host/join take on two independent Android
  runtimes; no fixture markers or debug overlays appear in chat.
- [ ] Both decoded video surfaces, room participants, play, pause, and seek are
  visible, with the corresponding native acceptance results retained.
- [ ] Chat and reaction are sent through the production UI and visible on the
  peer.
- [ ] Continue Watching resumes real saved progress.
- [ ] RevenueCat shot proves paywall, Test Store purchase, entitlement, and the
  newly allowed hosted session in one accepted production journey.
- [ ] Nearby appears only after physical Android-to-Windows proof; Cast appears
  only after hardware proof.
- [ ] Device/source labels are accurate; emulator footage is never called
  physical-device footage.
- [ ] Final render is under 2:00, has no copyrighted music, uses cleared demo
  media, and is watched end-to-end after export.
