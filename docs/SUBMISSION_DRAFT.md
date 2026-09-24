# MeowWatch Mobile — Devpost submission draft

> **Working draft; not ready to publish.** This is English project copy plus a
> completion checklist. [STATUS.md](STATUS.md) is the source for current product
> acceptance and remaining gates. The 98-second native review edit is
> not the final submission film. No publication or submission is represented here.

## Project name and tagline

**MeowWatch Mobile**

**Movie night, even when you're miles apart.**

## Short description

MeowWatch Mobile is an Android-first way for friends, partners and families to
watch the same video together. One person starts a room, another joins, and
play, pause and seek stay coordinated while chat and reactions keep the moment
social. The app also remembers where you stopped and includes a secure Nearby
companion for the existing MeowWatch desktop, with physical-device acceptance
still to complete.

## Inspiration

Remote movie nights often begin with a countdown: “Three, two, one, play.” A
small interruption means another countdown, and conversation moves to a second
app. The mechanics get in the way of the feeling people wanted in the first
place: sharing a screen and reacting together.

MeowWatch Mobile brings the controls and the conversation into one touch-first
experience. It is couples-first, but not couples-only; the same flow works for
friends, family or a small group watching from different places.

## What it does

- Starts or joins a Together Session without requiring an account.
- Offers a short, skippable first-use guide, available again from Settings.
- Accepts pasted invitations and room QR codes, showing room and server details
  for review before the user confirms Join.
- Plays supported direct media links and local files chosen through Android's
  native file picker. A subtle **Try a short film** action offers a ready-to-play
  sample through the same media flow.
- Coordinates play, pause and seek through a secure Syncplay room, with
  participant presence, chat and reactions beside the video.
- Saves playback progress and local last-watched dates for **Continue Watching**,
  keeps recent rooms accessible, and supports standalone viewing in **Local Mode**.
- Provides a shared playback-target model for the phone, the paired Nearby
  desktop companion and the implemented Cast sender. Physical Nearby and Cast
  receiver acceptance remain open.

The free product includes one real hosted Together Session per local calendar
day. Joining, reconnecting and changing playback targets do not consume another
session. **MeowWatch Plus** unlocks unlimited hosting, premium player appearances
and reactions through RevenueCat's real entitlement state.

Each participant needs access to the selected video; the app does not send a
host's private local file to other participants. Direct media links are distinct
from ordinary video-platform webpages: the app does not claim YouTube-page or
DRM playback. The sample is the unmodified Sintel trailer, credited to Blender
Foundation under CC BY 3.0 in [third-party notices](../THIRD_PARTY_NOTICES.md).

## How we built it

MeowWatch Mobile uses Flutter and Dart, with protocol and product logic kept
separate from widgets:

- A portable synchronization layer speaks the Syncplay protocol, preserving
  fail-closed STARTTLS validation.
- An Android playback adapter reports actual player position and state to the
  room; lifecycle handling pauses local playback and requires explicit resume.
- Local persistence keeps onboarding, playback history and daily hosting policy
  durable across app restarts.
- The official RevenueCat Flutter SDK loads Offerings and maps `CustomerInfo`
  to the `meowwatch_plus` entitlement.
- Nearby uses explicit pairing, pinned TLS, protected credentials and revocation
  instead of exposing an unauthenticated LAN remote.

The interface was designed for phones and tablets, with responsive layouts,
landscape controls, accessible text scaling and large touch targets. Automated
checks and native emulator journeys cover protocol behavior, actual playback,
responsive layouts, billing outcomes and persistence. Exact accepted builds,
failed runs and outstanding checks are maintained in [STATUS.md](STATUS.md).
Emulator results do not establish physical-device behavior. The native QR
journey decodes a generated invite image through Android ML Kit; it does not
establish camera-hardware scanning.

## Why RevenueCat belongs in the product

The free shared experience remains useful: people can join sessions, watch,
chat, react and resume a video. Plus serves people who host often, removing the
daily hosting limit and adding appearances such as Glass Aurora and Cinema Noir,
plus the Movie night reaction.

The official SDK drives the actual product benefits. Accepted Test Store
journeys exercise the free-session limit, native cancellation, failure and
successful purchase, entitlement refresh, Settings Restore, persisted
appearances, a premium reaction received by a peer, and two distinct paid hosted
sessions. Separate accepted SDK evidence covers same-customer process relaunch,
expiration and inactive Restore; it is not continuous video of the expiry wait.
Current evidence and remaining limitations are recorded in [STATUS.md](STATUS.md).

All demonstrated purchases use **RevenueCat Test Store, with no real charge**.
The purchase journey has **one native Android player and an independent headless
TLS peer**. Restore retains the same customer; it does not prove recovery after
reinstall or lost identity. Test Store evidence does not establish Google Play
production billing, store publication or physical-device billing. The normal
release build keeps purchases unavailable until a live platform key is
configured; the Test Store demonstration uses the development build.

## Relationship to the original desktop MeowWatch

MeowWatch Mobile is a new Android-first counterpart to the existing open-source
[Windows MeowWatch project](https://github.com/PeterShanxin/MeowWatch). The desktop
project already established the product idea and behaviors such as synchronized
playback, chat, reactions, Local Player Mode and Continue Watching. This project
does not present MeowWatch as a brand-new concept.

The mobile work lives in a separate repository and adds a touch-first UI,
Android playback and lifecycle handling, mobile persistence, RevenueCat billing,
responsive phone/tablet layouts and secure Nearby companion work. Portable
domain and protocol ideas are selectively adapted; Windows player, updater,
floating-window and desktop layout code are not treated as mobile implementations.
Both projects use **AGPL-3.0-only**. Reused code and assets retain their applicable
notices and provenance.

## Challenges and lessons

The difficult part was deciding which state is authoritative while two native
players, a public room, Android lifecycle events and network delay all change
at once. Tests therefore assert real player position and state instead of
treating a sent command as success. Matching position checkpoints also do not
prove smooth decoded video; native footage needs its own visual review.

Nearby control raised a similar lesson: convenience cannot come from silently
trusting the local network. Pairing needs explicit approval, scoped credentials,
pinned identity and revocation that removes control.

RevenueCat works best when it expresses a product rule. Separating billing from
the daily hosting policy keeps purchase, Restore, cancellation, reconnect and
target changes consistent.

## Complete before publishing this draft

1. Close the remaining product criteria in [STATUS.md](STATUS.md), including
   required physical Android and
   trusted-LAN Nearby checks, and Cast receiver proof or a precise genuine
   blocker with the best working fallback. P0/P1/P2 define implementation order;
   they are not optional submission scope.
2. Complete the required checks and a clean-install full demo rehearsal on the
   chosen final build. Preserve the distinction between widget, emulator,
   physical-device and camera evidence.
3. Finish a readable, smoothly recorded film strictly under two minutes. The
   current **98-second review edit** combines Together run `36037966143` at
   `9a3fc05` with Local/fullscreen/purchase sources at `6e46041`. These share the
   tablet-layout fix, with different test drivers and development/release
   runtimes. Later history/rate fixes have separate acceptance evidence.
   Source-held frames are retained; cloud render and review are pending. Its
   [demo script](DEMO_SCRIPT.md) retains original-speed cuts, source hashes,
   runtime labels and Test Store/Restore boundaries. It is not a final-build
   rehearsal, one uninterrupted take or submission-ready footage.
4. Confirm entrant and form requirements below, then replace this working
   notice and acceptance caveats only where the final evidence warrants it.
   Omitting a feature from the film does not close its product acceptance gate.

## Entrant and submission requirements

The entrant confirmed **active student status, local age of majority and
availability of an academic email** on 2026-09-17. No email address was collected;
recognition of its domain in the actual Devpost flow remains unverified.

Before final submission, the entrant must confirm residency, absence of
disqualifying conflicts, ownership/licensing for reused contributions and
assets, and final legal acceptance. The two organizer questions remain open:
whether the substantially developed new mobile counterpart qualifies under the
new-work rule, and how a no-store Next Gen entrant should answer a conflicting
store-release checkbox if the form requires it. See the sourced
[submission requirements](SUBMISSION_REQUIREMENTS.md); this draft does not
resolve that rules conflict or claim organizer approval.

## Submission assets and final checklist

- [ ] Final demo is strictly **under 2:00**, publicly viewable on YouTube or
  Vimeo, and shows the actual app with accurate runtime and purchase labels.
- [ ] Media, narration, music and assets have appropriate rights and attribution.
- [ ] Public repository has current build instructions, source/asset provenance,
  a visible AGPL-3.0-only license and a passing final secret scan.
- [x] The flat [app icon](../assets/brand/meowwatch-1024.png) is **1024 × 1024**,
  opaque and unmasked; exports are documented in the [brand kit](BRAND.md).
- [x] An original [native Home screenshot](../assets/submission/meowwatch-android-1179x2556.png)
  is **1179 × 2556**, without a device frame, resizing or cropping. Its
  [provenance](../assets/submission/screenshot-provenance.json) retains the
  `9b7e9ed` emulator source; it does not depict the newer guide or certify video.
- [x] The gallery thumbnail is prepared at **1200 × 800**, a 3:2 ratio.
- [x] RevenueCat project ID is `ca9218b2`, recorded in the
  [verified setup](REVENUECAT_SETUP.md).
- [ ] Academic email recognition, remaining eligibility, organizer clarification
  and final legal acceptance are complete.
- [ ] Devpost shows every required section complete and its final state is
  **Submitted**, with the public links checked after submission.
