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

**Acceptance notes:** All 11 workflows at `9b7e9ed` have finished: seven pass and
four fail. Native results use Android emulators. The independent phone/tablet
runtime matrix passes all three jobs. The full
[production Together journey 35212468221](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468221)
reaches real create/join, two-way native play/pause/seek, chat, reactions and peer
presence, then fails a Flutter semantics assertion during the extended
shared-link flow. Original footage also reveals an earlier app ANR dialog
obscuring the phone while widget automation continued beneath it. These steps
do not prove a normally operable user journey. Recordings exist with explicit
gaps, but the complete journey and paired demo film remain unaccepted; recovery
and repeated-room branches are not proved by the earlier steps.

The guide, Settings replay, Local playback, Continue Watching and actual
**Try a short film** button pass 20 steps with 14 screenshots on phone,
portrait tablet, landscape tablet and landscape phone in
[product journey 35212468253](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468253).
Small phone records those same app steps, then fails during Flutter semantics
teardown; its complete driver is not counted as passing. The sample uses the
unmodified Sintel trailer, credited to Blender Foundation under CC BY 3.0,
through the normal direct-media path. All five app observations decode its
52,209 ms duration and advance at least four seconds. Final raw-film inspection
remains separate from the app screenshots and assertions.

Release API 35 passes clean install and confirmed HTTPS/content-URI sharing,
with 12/9 seconds of observed playback advancement and a temporary read-only
content grant. Debug API 29/35 fail the new incoming-media harness checks;
corrections await native rerun. SAF relaunch independently retains its grant and
restores an eight-second playback position across two processes. Normal
lifecycle reaches real playback but fails recording validation; local metadata
and clock corrections do not establish HOME/resume/restart acceptance. Physical
Android-to-Windows Nearby control and Cast receiver acceptance remain open.

History now shows local last-watched dates, and room QR scanning leads to review
and explicit confirmation. Widget tests cover rejection, cancellation,
permission denial and scanner cleanup. The current Together guest reaches
joined playback after its required Android ML Kit image-decode step; this is
execution-prefix evidence, not camera hardware or a completed extended journey.
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
SDK. [Production journey 35212468110](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468110)
at `9b7e9ed` passes **all 12 stages**: a clean free customer, one free hosted
session, the next-host paywall, native cancellation/failure/success, Settings
restore and cache-invalidated restore, persisted Glass Aurora, a premium Movie
night reaction received by the TLS peer, persisted Cinema Noir, and two
distinct paid hosted sessions. Native playback advances in all three rooms.
The review confirms the actual theme, reaction, offering and restore screens.

[RevenueCat relaunch and expiry 35212468121](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35212468121)
also passes. The real Test Store purchase at 10:58:48 UTC expires at 11:03:48;
fresh SDK data observes inactive Plus at 11:03:52, and a cache-invalidated
restore keeps it inactive for that same customer and original purchase. This
uses the actual subscription expiry, without changing the clock or entitlement.

The purchase journey uses **one native Android player and a headless TLS peer
in one process**. Its restore checks retain the same customer; they do not
establish recovery after reinstall or lost identity. All billing evidence is
sandbox Test Store evidence, not a Google Play charge, store publication or
physical-device billing.

Reviewed purchase footage contains no unexpected system modal. Its three source
files have approximately **3.384/2.623-second playable gaps**, distinct from
the recorder's 1.281/1.705-second coverage gaps. Final editing must use explicit
cuts rather than imply uninterrupted actions across those boundaries.

The earlier `70575be` purchase run remains historical 10-stage evidence. The
prepared [native screenshot provenance](../assets/submission/screenshot-provenance.json)
still identifies that older build and its original recording hashes; it is not
relabeled as the new 12-stage run.

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

1. Resolve the extended Together failure and inspect a complete paired
   phone/tablet recording, including chat, reactions and shared video links.
2. Edit the accepted 12-stage purchase footage with its Test Store and
   same-customer restore labels, preserving the source segment boundaries.
3. Complete physical Android-to-Windows Nearby pairing and control acceptance,
   then include it only if the recording is stable.
4. Finish extended recovery/repeated-room acceptance and fresh debug
   incoming-media checks; resolve the remaining lifecycle and small-phone
   teardown failures. Inspect guide/sample recordings and complete the full
   clean-install demo rehearsal. Keep QR image-decoding and camera evidence
   clearly distinguished.
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
  Its provenance identifies the accepted `70575be` emulator capture. The image
  shows Home; it does not depict the new guide or establish clean video footage.
- [x] Gallery thumbnail is readable at a 3:2 ratio (1200 × 800).
- [x] RevenueCat project ID: `ca9218b2`, recorded from Project settings in
  [the verified setup](REVENUECAT_SETUP.md).
- [ ] Entrant eligibility and the unresolved Next Gen/new-work interpretation
  are confirmed.
- [ ] Devpost shows all sections complete and the final state is **Submitted**.
