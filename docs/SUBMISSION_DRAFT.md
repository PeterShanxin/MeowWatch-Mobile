# MeowWatch Mobile — Devpost submission draft

> **Working copy, not ready to publish.** The [acceptance ledger](STATUS.md)
> records current evidence and open product gates. The [demo script](DEMO_SCRIPT.md)
> tracks the exported 94-second film and its source footage. The Devpost
> [project page](https://devpost.com/software/meowwatch-mobile) is public with the
> copy below, cover, icon and screenshot; its hackathon entry is not submitted.

## Project name and tagline

**MeowWatch Mobile**

**Movie night, even when you're miles apart.**

## Short description

MeowWatch Mobile brings shared movie nights to Android. Start or join a room,
watch in sync, and talk beside the player with chat and reactions. Local viewing
and Continue Watching work between movie nights, too.

## Inspiration

A long-distance movie night can begin with “Three, two, one, play,” then need
another countdown every time someone pauses. Conversation lives in a separate
app. We wanted one place to watch, talk and pick up where you left off. The
design starts with couples, but works for friends, family and small groups.

## What it does

One person starts a Together Session and shares an invitation; another can
join by link, pasted invitation or QR code after reviewing the room and
server. Each person opens the same supported direct video URL or a local file
they can access. MeowWatch coordinates play, pause and seek through the room;
it does not upload one person's private video file to everyone else. Presence,
chat and reactions keep people together around the video.

Local Mode supports solo viewing. Continue Watching saves progress, and recent
rooms help start another movie night. A first-use guide and licensed sample
help new users try the flow. Ordinary video-platform webpages and protected
streams are outside direct-media support.

Free users can host one real Together Session per local calendar day. Joining
someone else, reconnecting and changing playback targets do not spend another
session. MeowWatch Plus adds unlimited hosting, player appearances and a
premium reaction. A secondary Nearby companion lets the phone control desktop
MeowWatch after explicit pairing; discovery, playback controls, saved reconnect
and revocation have been exercised on a physical Android phone and Windows PC.
The Cast sender still lacks physical receiver acceptance; phone playback is
the supported fallback.

## How we built it

Flutter and Dart provide the phone and tablet interface, while room protocol,
hosting policy and entitlement logic remain separate from widgets. A portable
Syncplay client uses fail-closed STARTTLS validation. Android's player reports
actual position and state to the room, and lifecycle and audio-focus handling
pause shared playback when interruption makes continued synchronization
unsafe. Local storage retains history, onboarding state and the daily hosting
ledger across process restarts.

Nearby pairing requires explicit approval, pinned TLS identity, protected
credentials and revocation. Automated checks and native Android emulator
journeys include independent phone and tablet clients. The [acceptance
ledger](STATUS.md) records the complete ordinary-APK clean-install rehearsal
and the remaining hardware limits. Matching positions do not prove identical decoded
frames or smooth footage.

## Why RevenueCat belongs here

Guests can still join, watch and talk for free. Plus serves frequent hosts.
The official RevenueCat Flutter SDK loads an Offering and
uses the `meowwatch_plus` entitlement to unlock actual hosting and appearance
benefits. Native emulator journeys cover purchase outcomes, Restore, a second
hosted Plus session and a premium reaction seen by a peer. The demonstration
uses **RevenueCat Test Store, with no real charge**. A physical Android phone
also exercises cancellation, failure, successful entitlement activation and
relaunch. This does not claim Google Play production billing. Current
evidence and limits are in [STATUS.md](STATUS.md).

## Desktop heritage and lessons

This is a new Android-first counterpart to the existing open-source
[MeowWatch desktop project](https://github.com/PeterShanxin/MeowWatch), which
already established synchronized playback, chat, reactions, Local Player Mode
and Continue Watching. The mobile repository adds a touch interface, Android
playback and lifecycle behavior, mobile persistence, RevenueCat integration
and companion work. Portable ideas and code are adapted with their provenance
and notices; both projects use **AGPL-3.0-only**.

The hardest question was which state to trust when native players, a shared
room and the network disagree. We learned to verify actual player state,
preserve a paused recovery path and tie evidence to its runtime. Convenient
Nearby control still needs explicit, revocable pairing.

## Before publishing

- [x] Rehearse the ordinary APK from a clean install through Together, history,
  quota, Test Store purchase, Restore and Local resume on two independent emulators.
- [x] Verify the final UI fixes after physical playback, purchase and trusted-LAN
  Nearby acceptance. Prove Cast on a receiver or document the unavailable
  receiver and working phone fallback.
- [x] Finish the ordinary local Windows/cloud Android check, with its media
  fallback and runtime limits documented in the acceptance ledger.
- [x] Obtain the desktop maintainer's final two-instance confirmation and merge
  desktop PR #279 at unchanged application source.
- [x] Verify desktop signed release `v0.51.0-alpha` and R2 metadata.
- [ ] Finish mobile repository closeout.
- [x] Watch the complete final film at normal speed, verify a duration strictly
  under two minutes, accurate runtime and Test Store labels, rights to every
  asset, and a public YouTube or Vimeo link. Follow the [demo script](DEMO_SCRIPT.md).
- [ ] Recheck the public repository, AGPL license visibility, desktop and asset
  provenance, setup instructions and final secret scan. Confirm the icon,
  original unframed 1179 × 2556 screenshot and gallery thumbnail are attached.
- [x] Register after the entrant's explicit rules/terms and eligibility confirmation.
- [x] Save the authorized academic email, artwork, Android platform, RevenueCat
  project ID and judge notes in the draft. The final Unlisted video is saved in
  the project and competition form (4/5 sections complete).
- [x] Verify the authenticated Devpost account uses the authorized academic email.
- [x] Recheck the September 25 submission fields against the entrant's existing
  rules/terms and eligibility confirmation. No additional mandatory
  ownership/new-work declaration is present. The form's first-version/store
  confirmation is optional and is left unanswered for the Next Gen path.
  See [submission requirements](SUBMISSION_REQUIREMENTS.md).
- [ ] Check every Devpost section and public link, then verify the final state
  says **Submitted**. A saved draft is not a submission.
