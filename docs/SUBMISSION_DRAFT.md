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
- Plays supported direct media links and local files selected through the
  native Android file picker.
- Coordinates play, pause, and seek through a secure Syncplay room.
- Keeps participant presence, chat, and reactions beside the video.
- Saves recent playback progress for **Continue Watching** and also works as a
  standalone player in **Local Mode**.
- Provides a playback-target model for watching on the phone or using the phone
  as a companion for a nearby MeowWatch desktop.

The free product includes one real hosted Together Session per local calendar
day; joining a room and reconnecting do not consume another session.
**MeowWatch Plus** unlocks unlimited hosting through RevenueCat's entitlement
state. The accepted emulator purchase journey is described below.

**Acceptance notes:** Two independent Android emulators passed two-way native
play, pause, seek and reaction checks at the earlier `f8fdd62` checkpoint.
The current `feaeb77` production Together and two-AVD matrix jobs fail; complete
production create/join/social footage remains unaccepted. Four current native
viewports pass direct-link playback and Continue Watching; phone-landscape was
rejected because it rendered portrait. File-picker selection, content-URI
playback and retained grants/history after a process restart also pass.

The production UI purchase-and-hosting journey and its native recording now
pass at `feaeb77`: **one native Android player and a headless TLS peer in the
same process**, not two recorded players. Nearby desktop control still needs
physical Android-to-Windows LAN acceptance. Cast hardware and the full normal
application lifecycle remain unaccepted. See [current evidence](STATUS.md).

**Locally implemented, awaiting native proof:** a skippable three-step
first-use guide with Settings replay, and **Try a short film**, which loads
the attributed Sintel trailer through the ordinary media path. New native
guide and exact-sample playback checks are prepared; earlier passing journeys
do not validate these additions.

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
SDK. [Production journey 35194003110](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35194003110)
at `feaeb77` passes **all 10 recorded stages**: a clean free customer, one free
hosted session, the next-host paywall, native cancellation, native failure,
successful purchase, Settings restore, restore after customer-info cache
invalidation, persisted Cinema Noir, and two distinct paid hosted sessions.
The same run records the localized price, activates `meowwatch_plus` and
observes real native playback with its TLS peer in all three sessions.

The native purchase-to-hosting recording is available; assembling and reviewing
the final demo remains open. This acceptance uses one Android player and a
headless protocol peer in one process. Restore retains the **same already-active
customer**; it does not establish recovery after reinstall or lost identity.
This is sandbox Test Store evidence, not a Google Play charge, store publication
or physical-device billing. The [native screenshot provenance](../assets/submission/screenshot-provenance.json)
retains the exact build, runtime, verified stages and original recording hashes.

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

1. Complete and inspect the production phone-and-tablet create/join recording,
   including real chat and reaction UI.
2. Edit the accepted production purchase footage into the final demo, preserving
   its sandbox and same-customer restore labels.
3. Complete physical Android-to-Windows Nearby pairing and control acceptance,
   then include it only if the recording is stable.
4. Pass the new guide/Sintel native checks, repeat the corrected phone-landscape
   gate, and complete lifecycle/product review and the full clean-install demo
   rehearsal.
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
  Its provenance identifies the accepted `feaeb77` emulator capture; later UI
  additions are not represented by that image.
- [ ] Gallery thumbnail is readable at a 3:2 ratio.
- [ ] RevenueCat project ID is copied from Project settings.
- [ ] Entrant eligibility and the unresolved Next Gen/new-work interpretation
  are confirmed.
- [ ] Devpost shows all sections complete and the final state is **Submitted**.
