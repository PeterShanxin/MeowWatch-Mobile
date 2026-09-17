# MeowWatch Mobile — Devpost submission draft

> **Draft status (2026-09-17): not ready to publish.** Product acceptance,
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

**Acceptance notes:** Native results use Android emulators. The current
`300ca2e` five-layout journey and recorded production purchase pass. Its
[paired Together run 35230867493, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867493)
also passes, with independent audit of both complete drivers, native logs and
the 216.667-second paired evidence film. The final under-two-minute submission
film has not been assembled. Normal incoming-video and lifecycle
follow-up gates, fresh proof for later fixes, and the complete clean-install
demo rehearsal remain open. The [current evidence ledger](STATUS.md) records
exact run outcomes and their boundaries.

The guide, Settings replay, Local playback, Continue Watching and actual
**Try a short film** button have 20 recorded steps and 16 screenshots per layout
in [product journey 35230867480](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867480).
All five complete drivers pass, including teardown, on the official unpatched
SDK. Short-landscape guide refinements made afterward need fresh native
recapture. The sample uses the unmodified Sintel trailer, credited to Blender
Foundation under CC BY 3.0, through the normal direct-media path. It does not
imply playback of ordinary YouTube or other platform webpages.

At `300ca2e`, normal debug API 29/35 and release API 35 builds install and start,
but their incoming-video observer rejects the intentional repeated media title;
its scoped correction awaits a complete rerun. Lifecycle stops during ADB
readiness preparation before app samples. Physical Android-to-Windows Nearby
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
SDK. [Production journey 35230867387, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867387)
at `300ca2e` passes **all 12 stages**: a clean free customer, one free hosted
session, the next-host paywall, native cancellation/failure/success, Settings
restore and cache-invalidated restore, persisted Glass Aurora, a premium Movie
night reaction received by the TLS peer, persisted Cinema Noir, and two
distinct paid hosted sessions. Native playback advances in all three rooms.
The retained recording covers 98.46% of the journey under unchanged coverage
limits. This newer acceptance does not change the older preview's source head.

[RevenueCat relaunch and expiry 35230867563](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867563)
at `300ca2e` also passes and has been audited. The same persisted customer
retains Plus across actual process IDs 2964 → 4960, with the old process absent
before relaunch and no uninstall or data clear. Its real Test Store purchase
at 14:11:44 UTC renews through 14:31:44, then expires at 14:36:44. Seven bounded
segments retain 49 fresh SDK observations. The request at 14:36:55.873 observes
inactive Plus, and cache-invalidated restore at 14:36:56.001 stays inactive for
the same customer, product and original purchase. No clock change or dashboard
entitlement override supplies the result. Only native Test Store
cancel/failure/success dialogs have video; there is no continuous recording of
the relaunch or expiry wait. The retained SDK evidence establishes those phases.

The purchase journey uses **one native Android player and an independent
headless TLS peer**. Its restore checks retain the same customer; they do not
establish recovery after reinstall or lost identity. All billing evidence is
sandbox Test Store evidence, not a Google Play charge, store publication or
physical-device billing.

The current local purchase chapter is a **40.2-second v2 review preview**, using
the same original `9b7e9ed` footage; the older 43-second v1 is historical. The
phone is about 25% larger, scope disclosures are more readable, and all footage
remains at 1× with direct cuts and full uncropped app frames. Complete decoding
and 52 sampled visual time points were checked; continuous viewing and final
film acceptance are still required. The [demo script](DEMO_SCRIPT.md) records
its source points and local package provenance.

The actual purchase-success heading is brief: v2 retains 0.4667 seconds with a
spinner still visible, followed by an explicit cut to real Settings showing
Plus active and the same-customer restore result. The original has no clean
2–3-second settled-success hold; its first enabled Done frame already contains
anomalous red/yellow room-loading text behind the sheet. Selecting a different
window does not fix that app appearance defect. Its correction and a clean
native recapture remain separate from editing. No confirmation is frozen,
slowed or generated to suggest a longer success state.

The three source files have approximately **3.384/2.623-second playable gaps**,
distinct from the recorder's 1.281/1.705-second coverage gaps. Final editing
must use explicit cuts rather than imply uninterrupted actions across those
boundaries. The preview retains Test Store/no-charge, same-customer restore and
one-native-player/headless-peer disclosures; it is not a finished submission
film or a filmed two-native-player purchase session.

The [native screenshot provenance](../assets/submission/screenshot-provenance.json)
identifies `9b7e9ed` and its original recording hashes. The later d946 purchase
run also passes 12 stages; ec856 fails recording coverage. Most recently,
[300ca2e purchase 35230867387, attempt 2](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35230867387)
passes all 12 stages. These later results do not replace the pinned source of
the screenshot or edited purchase chapter.

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

1. Select and frame shots from the audited `300ca2e` paired Together recordings,
   or a freshly validated presentation take, preserving real chat, reactions,
   source details and shared-video behavior. Review the complete final edit.
2. Integrate the 40.2-second purchase review chapter after continuous playback
   review, or select a fresh clean purchase take. Preserve Test Store,
   same-customer restore and headless-peer labels, and the actual source gaps.
3. Complete physical Android-to-Windows Nearby pairing and control acceptance,
   then include it only if the recording is stable.
4. Finish extended recovery/repeated-room acceptance, incoming-media and
   lifecycle follow-up checks, and fresh native proof for the latest guide
   and loading-overlay fixes. Inspect the chosen guide/sample recordings and
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
