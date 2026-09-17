# MeowWatch Mobile — Devpost submission draft

> **Draft status (2026-09-18): not ready to publish.** Product acceptance,
> final recording, entrant eligibility, and submission-form details still have
> open gates. Resolve the acceptance notes below before using this copy in
> Devpost; no publication or submission is represented here.

## Project name

**MeowWatch Mobile**

## Tagline

**Movie night, even when you're miles apart.**

## Short description

MeowWatch Mobile is an Android-first way for friends, partners, and families to
watch the same video together. One person starts a room, another joins, and
play, pause, and seek stay coordinated while chat and reactions keep the moment
social. The app also remembers where you stopped and is designed to let a phone
become a secure companion for a nearby MeowWatch desktop.

## Inspiration and the problem

Remote movie nights often begin with a countdown: “Three, two, one, play.” A
small interruption means another countdown, and conversation moves to a second
app. The mechanics get in the way of the feeling people wanted in the first
place: sharing a screen and reacting together.

MeowWatch Mobile brings the controls and the conversation into one touch-first
experience. It is couples-first, but not couples-only; the same flow works for
friends, family, or any small group that wants to watch together from different
places.

## What it does

- Starts or joins a Together Session without requiring an account.
- Offers a short, skippable first-use guide that can be replayed from Settings.
- Accepts room invitations by paste or QR scan, with room and server details
  shown for confirmation before joining.
- Plays supported direct media links and local files selected through the
  native Android file picker.
- Coordinates play, pause, and seek through a secure Syncplay room.
- Keeps participant presence, chat, and reactions beside the video.
- Saves playback progress and local last-watched dates for **Continue Watching**
  and recent rooms, and also works as a standalone player in **Local Mode**.
- Provides a playback-target model for watching on the phone or using the phone
  as a companion for a nearby MeowWatch desktop.

The free product includes one real hosted Together Session per local calendar
day; joining a room and reconnecting do not consume another session.
**MeowWatch Plus** unlocks unlimited hosting through RevenueCat's entitlement
state. The accepted emulator purchase journey is described below.

**Acceptance notes:** Native results use Android emulators. At `2fc3831`,
five-layout, normal install, lifecycle and production purchase workflows pass.
The later `6c44e415` runtime matrix passes all three native jobs after the stale
pause-position fix. The 2fc Together attempt stops on Launcher ANR before app
installation; the later `5137e58` production follow-up passes both complete
drivers, all cleanup and its independent native artifact audit. The earlier `300ca2e`
[paired Together run 35230867493, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867493)
also passes, with independent audit of both complete drivers, native logs and
the 216.667-second paired evidence film. The final under-two-minute submission
film is still under review: a complete 118-second Review Preview is assembled,
but the original paired footage has sparse motion. A compact-capture comparison
at `694b1ac` passes CI and its originals are being audited. RevenueCat's `9e032ba` diagnostic run passes
same-customer process relaunch, final expiration and inactive Restore; the
earlier contradictory result did not recur and its cause is still unproven.
The complete clean-install demo rehearsal remains open.
The [current evidence ledger](STATUS.md) records
exact run outcomes and their boundaries.

The guide, Settings replay, Local playback, Continue Watching and actual
**Try a short film** button have 20 recorded steps and 16 screenshots per layout
in [product journey 35236920763](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920763).
All five complete drivers pass, including teardown, on the official unpatched
SDK. The compact landscape guide's main instructions and controls are visible;
supplementary details remain scrollable. The sample uses the unmodified Sintel trailer, credited to Blender
Foundation under CC BY 3.0, through the normal direct-media path. It does not
imply playback of ordinary YouTube or other platform webpages.

At `2fc3831`, normal debug API 29/35 and release API 35 builds pass clean-install,
launch and incoming-media acceptance. The normal release lifecycle journey
passes background pause, explicit resume and saved-position process recovery.
Physical Android-to-Windows Nearby
control and Cast receiver acceptance remain open. Historical accepted checks
do not replace these remaining gates.

History now shows local last-watched dates, and room QR scanning leads to review
and explicit confirmation. Widget tests cover rejection, cancellation,
permission denial and scanner cleanup. The paired Together driver uses an
Android ML Kit image-decode step before joining; successful CI does not turn
that step into camera-hardware evidence. The original recordings have passed
their detailed audit; final demo shot selection remains.
The latest [evidence ledger](STATUS.md) controls these acceptance boundaries.

## How we built it

MeowWatch Mobile is a Flutter and Dart app with deliberately separate product
boundaries:

- a portable room and synchronization layer speaks the Syncplay protocol;
- an Android playback adapter reports real media position and state back to the
  room;
- widgets consume controller state rather than owning protocol or quota logic;
- local persistence keeps onboarding, playback history, and daily hosting
  policy durable;
- the official RevenueCat Flutter SDK loads Offerings and maps
  `CustomerInfo` to the `meowwatch_plus` entitlement; and
- Nearby uses explicit pairing, pinned TLS, protected credentials, and
  revocation instead of exposing an unauthenticated LAN remote.

The Android interface was designed for phones and tablets rather than resized
from desktop. It includes scroll-safe small-screen layouts, landscape player
controls, large touch targets, and accessible text scaling. Transport security
remains fail-closed where Syncplay expects STARTTLS.

Current automated and native checks cover protocol behavior, playback,
responsive layouts, billing outcomes, persistence, and secure pairing. Emulator
evidence is labeled as emulator evidence; it does not stand in for physical
hardware proof.

## Why RevenueCat belongs in the product

The basic shared experience stays useful for free: people can join sessions,
watch together, chat, react, resume a video, and use Nearby companion basics.
The paid benefit is easy to understand for people who host regularly:
Plus removes the once-per-day limit for starting hosted Together Sessions.

The development build uses RevenueCat Test Store through the official Flutter
SDK. [Production journey 35236920484](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35236920484)
at `2fc3831` passes **all 12 stages**: a clean free customer, one free hosted
session, the next-host paywall, native cancellation/failure/success, Settings
restore and cache-invalidated restore, persisted Glass Aurora, a premium Movie
night reaction received by the TLS peer, persisted Cinema Noir, and two
distinct paid hosted sessions. Native playback advances in all three rooms.
The retained recording covers 98.8717% of the journey under unchanged coverage
limits. This newer acceptance does not change the older preview's source head.

[RevenueCat relaunch and expiry 35230867563](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867563)
at the earlier `300ca2e` passes and has been audited. The same persisted customer
retains Plus across actual process IDs 2964 → 4960, with the old process absent
before relaunch and no uninstall or data clear. Its real Test Store purchase
at 14:11:44 UTC renews through 14:31:44, then expires at 14:36:44. Seven bounded
segments retain 49 fresh SDK observations. The request at 14:36:55.873 observes
inactive Plus, and cache-invalidated restore at 14:36:56.001 stays inactive for
the same customer, product and original purchase. No clock change or dashboard
entitlement override supplies the result. Only native Test Store
cancel/failure/success dialogs have video; there is no continuous recording of
the relaunch or expiry wait. The retained SDK evidence establishes those phases
for that head. The new `2fc3831` expiry run receives active Restore after a fresh
inactive sample. Its cause remains unproven. The later
[9e032ba diagnostic run 35240675074](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35240675074)
passes the same strict gate: customer identity survives PID 2994 → 4730,
52 fresh expiry observations show five consecutive five-minute periods, then
fresh SDK data at 16:06:03.883 UTC is inactive after the final 16:06:01 expiry.
Restore at 16:06:04.040 remains inactive. This successful run does not explain
the earlier anomaly or prove it cannot recur.

The purchase journey uses **one native Android player and an independent
headless TLS peer**. Its restore checks retain the same customer; they do not
establish recovery after reinstall or lost identity. All billing evidence is
sandbox Test Store evidence, not a Google Play charge, store publication or
physical-device billing.

The current local purchase chapter is a **42-second review preview** from the
accepted `2fc3831` recording. Five original-speed shots show the paywall and
cancellation, failed-purchase message and retry, native successful purchase,
Settings restore, themes, a reaction and a second paid room. The full phone
capture fits a 450 × 975 area; captions remain outside the app pixels.

The 1,260-frame export fully decodes, retains pinned source hashes and passes
source-clock correspondence checks. Fifty-three output samples were visually
inspected; an uninterrupted browser replay from 0:00 to 0:42 was checked with
screenshots at 0, 14, 28, 39 and 42 seconds. This is sampled visual inspection;
the clip remains a review preview, not the final whole-app film. Its success heading remains
brief (one second in the edit, initially with a spinner), followed by a clear cut
to the real Settings confirmation. No successful state is frozen or extended.

The three native sources have 1.068- and 0.738-second recording gaps. The edit
uses explicit cuts, preserves Test Store and same-customer restore disclosures,
and identifies the single native player with its independent headless peer.
The [demo script](DEMO_SCRIPT.md) records exact source intervals and hashes.
Earlier 43-second and 40.2-second `9b7e9ed` previews remain historical. The
[required screenshot](../assets/submission/screenshot-provenance.json) also
retains its original `9b7e9ed` source; it is not relabeled as a newer capture.

## Relationship to the original desktop MeowWatch

MeowWatch Mobile is a new Android-first counterpart to the existing open-source
Windows MeowWatch project. The desktop project already established the product
idea and mature behaviors such as synchronized playback, chat, reactions,
Local Player Mode, and Continue Watching. This submission does not present
MeowWatch as a brand-new concept. The original desktop source is available at
<https://github.com/PeterShanxin/MeowWatch>.

The mobile work lives in a separate repository and adds a new touch-first UI,
Android playback and lifecycle handling, mobile persistence, RevenueCat
billing, responsive phone/tablet layouts, and secure Nearby companion work.
Portable domain and protocol ideas are selectively adapted where appropriate;
Windows player, updater, floating-window, and desktop layout code are not
treated as mobile implementations. Both projects use **AGPL-3.0-only**, and
reused code must retain its applicable notices and provenance.

**Entrant prerequisites:** active student status, local age of majority and
availability of an academic email were confirmed on 2026-09-17. The actual
Devpost email-domain check remains open. Before submission, confirm residency,
absence of disqualifying conflicts, ownership/licensing for reused contributions
and assets, and the organizer's treatment of a substantially developed mobile
counterpart to the earlier desktop project. Final legal acceptance remains with
the entrant.

## Challenges and lessons

The difficult part was not drawing synchronized controls; it was deciding which
state is authoritative while two native players, a public room, Android
lifecycle events, and network delay all change at once. Tests therefore assert
real player position and state instead of treating a sent command as success.

Nearby control raised a similar lesson: convenience cannot come from silently
trusting the local network. Pairing needs explicit approval, scoped credentials,
pinned identity, and revocation that actually removes control.

RevenueCat also works best when it expresses a product rule rather than opening
an isolated purchase screen. Separating billing from the daily hosting policy
keeps purchase, restore, cancellation, reconnect, and target changes consistent.

## What is next

Before submission:

1. Finish motion-quality review of the new compact capture and replace the
   sparse-motion 5137e58 paired chapter if its native originals are better.
   Preserve real chat, reactions, source details and shared-video behavior.
2. Review the complete 118-second edit, including its Local and 42-second
   purchase chapters, or select fresh accepted footage. Preserve Test Store,
   same-customer restore and headless-peer labels, and the actual source gaps.
3. Complete physical Android-to-Windows Nearby pairing and control acceptance,
   then include it only if the recording is stable.
4. Finish repeated-room acceptance and all required checks on the final head.
   Retain diagnostics for the earlier expiry/restore anomaly, which did not
   recur in the passing diagnostic run. Inspect the chosen guide/sample recordings and
   complete the full clean-install demo rehearsal. Keep QR image-decoding and
   camera evidence clearly distinguished.
5. Package the final icon, frame-free required screenshot, public source link,
   and a public video shorter than two minutes.

Cast will be included only after successful hardware verification. Otherwise it
will be omitted rather than represented by a simulated or unstable screen.

## Submission asset checklist

- [ ] Final demo is **strictly under 2:00**, publicly viewable on YouTube or
  Vimeo, and shows the actual Android app.
- [ ] Video uses owned or properly licensed media and no copyrighted music or
  third-party branding without permission.
- [ ] Public repository contains build instructions, assets, provenance, and a
  visible AGPL-3.0-only license; final secret scan passes.
- [x] Final flat cat-and-play [app icon](../assets/brand/meowwatch-1024.png) is
  exactly **1024 × 1024 px**, opaque and unmasked; platform exports are in the
  [brand kit](BRAND.md).
- [x] An original [native home screenshot](../assets/submission/meowwatch-android-1179x2556.png)
  is exactly **1179 × 2556 px**, without a device frame, resizing or cropping.
  Its provenance identifies the accepted `9b7e9ed` emulator capture. The image
  shows Home; it does not depict the new guide or establish clean video footage.
- [x] Gallery thumbnail is readable at a 3:2 ratio (1200 × 800).
- [x] RevenueCat project ID: `ca9218b2`, recorded from Project settings in
  [the verified setup](REVENUECAT_SETUP.md).
- [ ] Entrant eligibility and the unresolved Next Gen/new-work interpretation
  are confirmed.
- [ ] Devpost shows all sections complete and the final state is **Submitted**.
