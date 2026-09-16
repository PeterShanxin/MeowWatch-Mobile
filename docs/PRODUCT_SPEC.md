# MeowWatch Mobile - Shipaton 2026 Product & Engineering Spec

**Status:** Implementation-ready draft  
**Date:** 2026-09-16  
**Target repo:** `PeterShanxin/MeowWatch-Mobile`  
**Reference desktop repo:** `PeterShanxin/MeowWatch`  
**License:** AGPL-3.0-only, matching the desktop project  
**Primary target:** Android first  
**Secondary target:** iOS-ready architecture, but iOS must not block Shipaton delivery

> This document is the source of truth for the first Shipaton build. Implement toward the product outcome and acceptance criteria, not toward blindly reproducing the Windows UI. Use engineering judgment to resolve small details without waiting for approval.

---

## 1. Executive summary

Build **MeowWatch Mobile**, a mobile-first evolution of MeowWatch for watching videos together remotely.

The product should feel like one coherent app with multiple playback targets, not separate "mobile player", "remote", and "couple app" products.

### Product promise

> **Watch together, wherever you are.**

### Positioning

MeowWatch is **couples-first, but not couples-only**.

The clearest product and Shipaton story is long-distance movie night: two people who care about each other can still share the feeling of pressing play together. The same product must remain natural for friends, family, or any small group.

Suggested outward-facing message:

> **Movie night, even when you're miles apart.**
>
> Watch together with synchronized playback, chat, reactions, and any screen you like.

Do not add couple-binding mechanics, relationship streaks, anniversary systems, or other features that would unnecessarily restrict the product to romantic couples.

A user joins one MeowWatch room and can choose where playback happens:

1. **Watch on this phone** - the phone plays the media and participates directly in synchronized playback.
2. **Connect to nearby MeowWatch** - a nearby desktop plays the media while the phone becomes the companion screen for controls, chat, reactions, and room state.
3. **Cast to TV / receiver** - where technically feasible, use an external playback target while the phone remains the room controller.

The room, people, chat, playback state, and history should remain conceptually consistent regardless of playback target.

This is **not** a pixel-for-pixel Windows port. Reuse the mature ideas and portable core logic from desktop, then redesign the UX for touch and mobile usage.

---

## 2. Shipaton delivery constraints

The intended submission path is **Shipaton 2026 - Next Gen Award**.

Current official requirements relevant to this build:

- Submission deadline: **2026-09-30 23:45 Pacific Time**.
- Next Gen projects must be new or created / substantially developed during the submission window.
- Android is an eligible platform.
- Next Gen does not require an app-store release or paid Apple/Google developer account.
- The repository must be **public and open source**, including source, assets, setup instructions, and a visible open-source license.
- The target `MeowWatch-Mobile` repository must remain **public** for the Next Gen submission path.
- Use **AGPL-3.0-only**, matching desktop MeowWatch, unless an actual dependency/license conflict requires a change.
- The app must use the **RevenueCat SDK** for at least one purchase flow or RevenueCat Ads.
- Demo video must be **under 2 minutes** and show the actual working app.
- Submission needs a **1024 x 1024 icon** and at least one **1179 x 2556** screenshot without a device frame.
- Third-party SDKs, APIs, media, and assets must be used in accordance with their licenses and terms.

### RevenueCat implementation note

Use the official Flutter RevenueCat SDK (`purchases_flutter`) and keep billing behind a small abstraction.

For development without a Google Play/App Store setup, RevenueCat documentation supports its **Test Store**. Use that for early end-to-end entitlement work. Before final Shipaton submission, verify the accepted Next Gen purchase-testing path against the latest Shipaton guidance. If Test Store is not sufficient for judging, switch the billing adapter to an accepted RevenueCat web purchase flow rather than rewriting product logic.

---

## 3. Relationship to desktop MeowWatch

Desktop MeowWatch already proves the product concept and contains mature behavior that should be selectively ported.

The mobile repo must remain clearly identifiable as substantial new work:

- new repository and commit history;
- new mobile UI and interaction model;
- Android playback implementation;
- mobile navigation and lifecycle handling;
- mobile RevenueCat integration;
- nearby-device discovery / pairing;
- companion protocol and UI;
- optional cast integration;
- mobile-specific permissions, deep links, sharing, testing, and packaging.

### Reuse policy

Prefer reuse of **pure Dart domain/protocol logic** where it reduces risk.

Good candidates to inspect and selectively port from `PeterShanxin/MeowWatch`:

- `lib/core/sync/`
- `lib/core/session/`
- `lib/core/connect/`
- `lib/core/chat/`
- portable pieces of `lib/core/data/`
- portable media/session models

Do **not** blindly copy:

- Windows-specific player implementation;
- desktop floating-window assumptions;
- Windows updater/release logic;
- drag-and-drop UX;
- desktop layout code;
- Windows-only yt-dlp/Deno provisioning;
- code whose platform assumptions are unclear without tests.

When code is reused, preserve relevant copyright/license notices and keep provenance obvious in commit history or documentation.

---

## 4. Product principles

1. **Fast to start**
   - Create or join a room in seconds.
   - Avoid configuration screens before the first watch session.

2. **No countdowns**
   - Play, pause, and seek should synchronize automatically.

3. **Mobile-native**
   - Touch-first controls, bottom sheets, share sheet, QR/deep links, lifecycle-safe behavior.
   - Do not shrink the desktop UI onto a phone.

4. **One room, many screens**
   - Playback target is an implementation detail, not a different product.

5. **Social but not noisy**
   - Chat, reactions, presence, and typing should augment the video rather than dominate it.

6. **Core experience stays free**
   - Do not paywall the basic ability for two people to watch together.

7. **Secure by default**
   - Keep the desktop project's fail-closed attitude toward Syncplay transport.
   - Nearby control must not become an unauthenticated LAN remote.

8. **Demoable**
   - Every P0 feature must be reliable enough to show live in a two-minute video.

---

## 5. Core user journeys

### 5.1 First launch

1. Open app.
2. See a brief value proposition and optional display-name field.
3. If blank, offer a friendly generated name.
4. Land on Home.

Do not require account creation for the Shipaton build.

### 5.2 Create a watch room

1. Tap **Start a room**.
2. App selects a working public Syncplay endpoint automatically.
3. Generate / join the room.
4. Show:
   - friendly room code;
   - share button;
   - QR code or deep-link invite if implemented;
   - current participants.
5. Ask where to watch:
   - **This phone**
   - **Nearby MeowWatch**
   - **Cast** if an eligible target is available.

### 5.3 Join a room

Support at least:

- paste/type room code;
- pasted MeowWatch invite link;
- QR/deep-link join if ready.

On join, display current participants and media state.

### 5.4 Watch on phone

1. User chooses media.
2. App plays locally.
3. Play/pause/seek sync through the room.
4. Peer actions converge without manual countdown.
5. Chat/reactions remain accessible during playback.

### 5.5 Companion mode

1. Tap the playback-target/device button.
2. Discover nearby MeowWatch desktop instances.
3. Select a device.
4. Perform explicit pairing.
5. Phone becomes companion UI:
   - play/pause;
   - seek;
   - current title/time;
   - participant state;
   - chat;
   - reactions;
   - optional media-load action.
6. Desktop remains the actual Syncplay/player session where possible so the room does not gain duplicate ghost participants.

### 5.6 Continue watching

Show recent sessions with:

- media title;
- room/partner context when useful;
- last position;
- timestamp;
- resume action.

Resume into the correct local/room context without resetting progress.

### 5.7 Local mode

Allow MeowWatch to function as a normal mobile player without an active Syncplay connection.

The user should be able to enter or leave synchronized mode without losing the loaded-media context where technically safe.

---

## 6. Feature inheritance from desktop

| Desktop capability | Mobile adaptation | Priority |
| --- | --- | --- |
| Precision Syncplay synchronization | Port protocol/domain logic and bind it to mobile playback adapter | **P0** |
| Create/join room | Mobile-native create/join/share flow | **P0** |
| Automatic public Syncplay endpoint discovery | Preserve discover-and-join behavior with secure Hello validation | **P0** |
| STARTTLS fail-closed behavior | Preserve security invariant | **P0** |
| Chat | Mobile overlay/bottom sheet instead of movable desktop card | **P0** |
| Reactions | Lightweight bursts over video + reaction picker | **P0** |
| Typing indicators | Compact room/chat signal | **P0** |
| Presence connect/disconnect/reconnect messages | Keep, but visually quiet | **P0** |
| Smart auto-pause on peer/sync loss | Preserve with mobile lifecycle awareness | **P0** |
| Continue Watching / resume | Mobile history and one-tap resume | **P0** |
| Local Player Mode | First-class mobile mode | **P0** |
| Load local video | Android file picker / share intent | **P0** |
| Direct media URL | Paste/open link if the mobile player supports it | **P0** |
| Peer shared URL one-click load | "Watch this too" action | P1 |
| General webpage URL via yt-dlp | Do not port Windows provisioning blindly; evaluate separately | P2 / optional |
| Random friendly username | Reuse/adapt | P1 |
| Cozy / Cinema Noir / Glass Aurora themes | Mobile design language + optional theme selector | P1 |
| What's New/update UI | Not needed for Shipaton MVP | P2 |
| Signed desktop auto-updater | Not applicable to Android MVP | Out |
| Floating draggable chat card | Replace with mobile-native overlay/bottom sheet | Out as-is |
| Desktop drag and drop | Replace with picker/share sheet | Out as-is |

Desktop reference behaviors worth preserving include the mature sync/chat stack, local player mode, one-click peer URL workflow, continue-watching behavior, and automatic endpoint discovery.

---

## 7. New mobile-first features

### 7.1 Playback target switcher - P0 architecture

Create a `PlaybackTarget` abstraction rather than scattering target-specific checks through the UI.

Conceptually:

```text
RoomSession
  |
  +-- PlaybackTarget
        |
        +-- LocalMobileTarget
        +-- NearbyDesktopTarget
        +-- CastTarget
```

A target should expose a consistent minimal contract:

```text
load(media)
play()
pause()
seek(position)
positionStream
durationStream
playingStream
mediaStream
connectionStateStream
```

The synchronization layer should operate against this contract where practical.

### 7.2 Nearby MeowWatch - P0

Goal: the phone can quickly find and pair with a desktop MeowWatch on the same LAN.

Preferred discovery:

- mDNS / Android NSD, with a service such as `_meowwatch._tcp`;
- QR/manual fallback so discovery failure never blocks pairing.

Security:

- never accept arbitrary unauthenticated LAN control;
- use an explicit short-lived pairing token/challenge;
- user should see/approve the device being paired;
- bind the bridge to local interfaces only;
- do not expose the desktop control API to the public internet.

Recommended division of responsibility:

- Mobile repo owns discovery client, pairing UI, bridge client, and companion UX.
- If the desktop requires a bridge/advertisement server, implement it as a **small separate desktop PR** after the mobile contract is stable.
- Do not merge the mobile project into the old desktop repo merely to make discovery easier.

Minimal companion protocol should carry:

- device identity/capabilities;
- room/session state;
- media metadata;
- play/pause/seek commands;
- position updates;
- participant roster;
- chat/reaction send + receive;
- disconnect/reconnect status.

Avoid duplicate Syncplay users: in companion mode, prefer relaying through the desktop session instead of making the phone independently join the same room.

### 7.3 Cast / external playback - P1, strong stretch goal

Expose Cast in the same playback-target selector.

Preferred initial target:

- Google Cast / Chromecast-compatible devices on Android.

Scope carefully:

- start with media that the receiver can actually access, such as a direct HTTPS media URL;
- local-file casting may require a temporary local HTTP server and is not required for P0;
- do not attempt to bypass DRM or protected streaming-service restrictions;
- cast playback must still surface position/play-state to the synchronization layer.

If Cast integration becomes unstable or SDK-heavy, ship a polished nearby-desktop flow first. Cast must not jeopardize the core submission.

### 7.4 Android share/open flow - P1

Where practical:

- "Open with MeowWatch" for supported media links/files;
- Android share intent into MeowWatch;
- MeowWatch invite links should deep-link into Join.

### 7.5 Couple/social layer - P1, lightweight

Do not create a separate "couples app." Add only features that improve repeated two-person use:

- remember a frequent partner / recent room;
- one-tap "watch together again";
- recent sessions;
- optional small shared reaction/theme touches.

Avoid building accounts, cloud social graphs, streak systems, or a full watchlist backend for Shipaton.

---

## 8. Monetization / RevenueCat

### Requirement

RevenueCat integration is a **Shipaton submission requirement**, not an optional bonus. All Shipaton submissions must use the RevenueCat SDK for in-app purchases, subscriptions, or ads.

For MeowWatch, use a simple subscription model that monetizes **hosting frequency** without blocking guests from joining.

### Product model

#### Free

- **Host 1 Together Session per local calendar day**
- **Join other people's rooms without a daily limit**
- Core synchronized playback
- Chat and standard reactions
- Continue Watching
- Local Player Mode
- Nearby companion basics

#### MeowWatch Plus

Entitlement: `meowwatch_plus`

Primary paid benefit:

- **Unlimited Together Sessions**

Secondary benefits may be included when they are already polished:

- premium themes;
- premium reaction packs;
- additional room personalization;
- advanced host controls;
- future larger-group features.

Do **not** weaken the free product by unnecessarily paywalling ordinary joining, basic sync, or basic chat.

### Why only the host is metered

MeowWatch is inherently multiplayer. Requiring both participants to pay creates a bad network effect and makes inviting a new user harder.

The host is the natural payer:

1. A free user can invite anyone.
2. The guest can install MeowWatch and join immediately without encountering a subscription wall.
3. A user who repeatedly organizes watch sessions has demonstrated recurring value and is the appropriate conversion target.
4. This produces a clear RevenueCat paywall moment without breaking the first successful watch-together experience.

### Definition of a Together Session

Do **not** consume the free daily session simply when the user taps "Start a room."

A hosted Together Session counts only when all of the following occur:

1. the user is the room host/creator;
2. at least one peer successfully joins;
3. synchronized playback becomes active, or an equivalent explicit session-start event occurs.

Once started, the same session remains valid through:

- temporary disconnect/reconnect;
- app background/foreground transitions;
- playback target changes;
- switching between phone and nearby desktop;
- reasonable room re-entry after interruption.

Do not charge another session because of a crash, network interruption, or reconnect.

For the Shipaton build, a locally persisted `lastFreeHostedSessionDate` is acceptable. Architect the quota policy behind a small interface so it can later move to authenticated/server-backed accounting if MeowWatch becomes a commercial service.

### Paywall moment

When a Free user has already used today's hosted session and tries to start another:

1. Let the user complete the normal "Start a room" intent.
2. Before committing a new paid-only hosted session, present a compact MeowWatch Plus paywall.
3. Primary CTA: **Unlock unlimited watch sessions**
4. Secondary CTA: **Maybe tomorrow**
5. Also expose **Restore purchases**.

Do not show the paywall on app launch, on first install, or when joining another person's room.

### Subscription products

Keep the Shipaton product catalog deliberately small.

Recommended initial offering:

```text
Entitlement
  meowwatch_plus

Offering
  default
    monthly
    annual (optional if configuration is trivial)
```

One monthly subscription is sufficient for the first implementation. Add annual only if it does not create extra release risk.

Use RevenueCat Offerings so product identifiers and pricing are not hardcoded into UI logic.

### Pricing

Pricing is intentionally not fixed in this spec.

For Shipaton, first prove the purchase -> `meowwatch_plus` entitlement -> unlimited hosting flow with RevenueCat Test Store. Before any real commercial launch, choose regional pricing based on store price tiers and user testing rather than inventing a permanent price during the hackathon.

### Engineering

Create a billing boundary:

```text
BillingService
  configure()
  customerInfoStream
  isPlus
  presentUpgrade()
  restore()
```

Create a separate quota policy:

```text
HostingAccessPolicy
  canHostNow()
  remainingFreeHostsToday()
  recordSessionStarted()
```

The UI should ask these abstractions for access. Do not scatter RevenueCat SDK calls or date/quota checks through widgets.

Expected flow:

```text
User taps Start a room
        |
        v
HostingAccessPolicy.canHostNow()
        |
        +-- Plus ----------------------> allow
        |
        +-- Free + unused daily host -> allow
        |
        +-- Free + daily host used ---> RevenueCat paywall
                                             |
                                             +-- purchase succeeds -> entitlement active -> allow
                                             |
                                             +-- cancel/fail -------> return safely
```

### RevenueCat testing

Use RevenueCat Test Store during development so the full flow works without an App Store / Google Play billing setup:

- purchase succeeds;
- purchase fails;
- purchase cancelled;
- entitlement activates;
- entitlement expires;
- restore/customer-info behavior;
- app relaunch with entitlement state.

Use the official Flutter SDK (`purchases_flutter`).

Never commit secret/server RevenueCat keys. Only the appropriate client/public SDK key may be present in a client build.

Before final Shipaton submission, verify the latest Next Gen judging guidance for the accepted purchase-testing path and replace Test Store configuration if the competition requires another demonstrable path.

### Acceptance criteria

- [ ] First real hosted Together Session of the day works without a paywall.
- [ ] Guests can join rooms without consuming a hosting allowance.
- [ ] Starting another hosted session that day produces the Plus paywall.
- [ ] Purchasing Plus through RevenueCat immediately unlocks unlimited hosting.
- [ ] Restore purchases restores Plus access.
- [ ] Cancelling/failing purchase does not corrupt room/session state.
- [ ] Reconnecting to an existing session does not consume another free session.
- [ ] Changing playback target does not consume another free session.
- [ ] The quota/paywall path is easy to demonstrate in the Shipaton video without fake UI.

## 9. Recommended architecture

### Stack

- Flutter / Dart
- Android first
- latest stable Flutter compatible with required packages
- RevenueCat Flutter SDK
- SQLite/Drift or equivalent local persistence if reusing the desktop data model remains clean
- platform player selected for reliable Android local/direct-URL playback
- platform-specific integrations behind adapters

### Suggested package layout

```text
lib/
  app/
  core/
    room/
    sync/
    session/
    chat/
    media/
    playback/
    nearby/
    cast/
    billing/
  data/
    db/
    repositories/
  platform/
    android/
  ui/
    home/
    join/
    room/
    player/
    chat/
    devices/
    paywall/
    settings/
```

### Important boundary

The synchronization protocol must not depend directly on Flutter widgets or a specific player.

Keep commands-in / streams-out style where it remains useful.

---

## 10. Media support

### P0

Support reliably:

1. local user-selected video files that Android can decode;
2. direct HTTP/HTTPS media URLs supported by the chosen player.

### P1

- one-click load of a peer-shared compatible URL;
- Android share/open intents.

### Not required for MVP

The Windows app's generic webpage URL resolver uses yt-dlp/Deno-style desktop tooling. Do not force this onto Android.

If a clean, legal, mobile-compatible resolver emerges, add it later behind `MediaResolver`. Otherwise show a clear unsupported-link error and keep direct URLs/files reliable.

---

## 11. UX specification

### Visual direction

Keep the MeowWatch personality:

- cozy;
- cinematic;
- cat identity used sparingly;
- polished rather than childish;
- dark-first visual design;
- subtle glass/translucent surfaces where performance permits.

The app should feel related to desktop MeowWatch without copying desktop proportions.

Accessibility:

- adequate text/control contrast;
- do not encode important status using color alone;
- large touch targets;
- captions/labels for important icons;
- respect text scaling where practical.

### Home

Primary actions:

- **Start a room**
- **Join a room**

Secondary:

- Continue Watching
- Local mode
- Settings / profile

Avoid dashboard clutter.

### Room / player screen

Top or overlay:

- room/connection state;
- participant avatars/names;
- playback target button.

Main:

- video surface or companion now-playing surface.

Bottom:

- scrubber;
- play/pause;
- elapsed / duration;
- chat/reaction access;
- device/target selector.

Chat should appear as a sheet/overlay and remain usable in landscape.

### Empty/waiting states

Use the existing MeowWatch cat personality:

- waiting for friend;
- no video loaded;
- reconnecting;
- no nearby devices.

Make errors actionable, not just red text.

---

## 12. P0 Shipaton scope

A build is **submission-ready** only when all of these work:

### Project/repo

- [ ] New `MeowWatch-Mobile` repo
- [ ] AGPL-3.0-only license visible
- [ ] README with setup/build/demo instructions
- [ ] clear note that this is the mobile counterpart to the existing desktop MeowWatch
- [ ] Android build reproducible from a clean checkout
- [ ] no secrets committed

### Core mobile app

- [ ] Home / create / join flow
- [ ] friendly generated username or equivalent low-friction identity
- [ ] public Syncplay endpoint discovery
- [ ] secure Syncplay session establishment
- [ ] room roster/presence
- [ ] mobile local playback
- [ ] local video selection
- [ ] direct media URL load
- [ ] synchronized play/pause/seek between two actual clients
- [ ] chat
- [ ] reactions
- [ ] typing/presence behavior
- [ ] smart handling of disconnect/reconnect
- [ ] Continue Watching / resume
- [ ] Local Mode

### Companion

- [ ] discover or manually pair with nearby MeowWatch desktop
- [ ] explicit authenticated pairing
- [ ] show desktop now-playing/room state
- [ ] play/pause
- [ ] seek
- [ ] chat/reaction relay
- [ ] clean disconnect/reconnect

### RevenueCat

- [ ] SDK integrated
- [ ] entitlement state works end-to-end
- [ ] at least one visible Plus feature is actually gated/unlocked
- [ ] restore/customer-info behavior handled
- [ ] final Next Gen testing path verified against current competition guidance

### Polish

- [ ] portrait UX
- [ ] landscape player UX
- [ ] loading/empty/error states
- [ ] no obvious placeholder UI
- [ ] icon
- [ ] Shipaton screenshot
- [ ] stable demo path

---

## 13. P1 if P0 is stable

Prioritize in this order:

1. **Cast / Google Cast**
2. QR invite/pairing
3. deep-link room invites
4. Android share/open intents
5. peer-shared URL one-click load
6. premium themes/reaction packs
7. favorite partner / "watch again"
8. extra animation/polish

Do not start P1 while P0 sync or companion mode is flaky.

---

## 14. Explicit non-goals for Shipaton

Do not spend the deadline on:

- full account/auth backend;
- cloud database unless absolutely required;
- voice/video calling;
- full social network;
- recommendation engine;
- Netflix/Disney+/Prime/other DRM playback integration;
- bypassing protected media or service restrictions;
- a mobile yt-dlp port merely for feature parity;
- iOS build if it blocks Android completion;
- Windows updater work;
- pixel-perfect desktop parity;
- large-group scaling beyond what is needed to demonstrate the product;
- refactoring the desktop repo unrelated to the mobile bridge.

---

## 15. Reliability and security acceptance criteria

### Sync

- Two clients can join the same room repeatedly without manual server configuration.
- Play/pause/seek converge reliably under a normal home/mobile network.
- A stale/broken public endpoint is skipped when discovery is allowed.
- Transport security remains fail-closed where the Syncplay protocol expects STARTTLS.

### Mobile lifecycle

Test:

- foreground -> background -> foreground;
- screen rotation;
- incoming interruption;
- network temporarily lost/recovered;
- peer disconnect/reconnect;
- app killed/reopened with Continue Watching.

No silent room duplication or destructive state reset.

### Nearby pairing

- No command is accepted before pairing/authentication.
- Pair tokens are short-lived.
- Remote control is LAN-scoped.
- Disconnecting/revoking a pairing actually stops control.

### Media

- Unsupported media fails with a clear explanation.
- No "tap did nothing" states.
- A failed media load leaves the app recoverable.

---

## 16. Test strategy

### Unit tests

Prioritize pure logic:

- room-code parsing;
- endpoint discovery policy;
- sync state/convergence logic;
- playback-target state machine;
- companion protocol serialization;
- resume/history rules;
- entitlement mapping;
- pairing-token expiry.

### Widget tests

Cover key funnels:

- Home -> Start room
- Home -> Join room
- choose playback target
- media load failure/success
- chat/reaction UI
- paywall/Plus entitlement state

### Integration/manual tests

Minimum real-device matrix:

1. Android phone A + Android phone B
2. Android phone + Windows MeowWatch desktop
3. Android local mode
4. RevenueCat test entitlement
5. Cast target, only if implemented

Prefer real hardware for the final demo path.

---

## 17. Shipaton demo target

The build should support a clean <2 minute story.

### Suggested video flow

**0:00-0:10 - Problem**  
"Long-distance movie night should not require 3-2-1-play."

**0:10-0:25 - Create and join**  
Phone A starts a MeowWatch room. Phone B joins from the room code/link.

**0:25-0:55 - Synchronized mobile playback**  
Load a video, then demonstrate play/pause/seek staying synchronized.

**0:55-1:10 - Social layer**  
Send chat, reaction, show presence/typing briefly.

**1:10-1:30 - Nearby desktop companion**  
Phone discovers/pairs with desktop MeowWatch and controls the same experience from the phone.

**1:30-1:42 - Cast**  
If production-stable, switch target to a Cast device. If not, omit this section entirely.

**1:42-1:52 - RevenueCat**  
Open MeowWatch Plus and unlock/show a premium theme/reaction feature.

**1:52-2:00 - Close**  
"MeowWatch - watch together, wherever you are."

Never put an unstable feature in the submission video just because it exists in a branch.

---

## 18. Success definition

The Shipaton build succeeds if a judge can understand it immediately and the demo proves:

1. two people can watch the same media in sync;
2. it works as a real mobile product, not a desktop resize;
3. chat/reactions make it socially useful;
4. a phone can naturally become a companion for a nearby MeowWatch desktop;
5. RevenueCat is integrated into a believable product model;
6. the project is polished enough to feel shippable.

The goal is **not maximum feature count**.

The goal is:

> **a small number of highly visible features that work extremely well.**

---

## 19. Implementation order

Follow this order unless a discovered technical dependency makes a different order clearly better.

### Phase 0 - Repo and technical spike

- Create new repo.
- Flutter Android skeleton.
- License/README/CI.
- Prove Android playback.
- Prove portable Syncplay core can connect securely.
- Prove RevenueCat SDK initializes.

**Gate:** do not design the full UI before sync + playback feasibility is proven.

### Phase 1 - Core room loop

- Home/create/join.
- Endpoint discovery.
- Room session.
- Local playback target.
- play/pause/seek sync.
- roster/presence.

**Gate:** two real devices complete the core loop.

### Phase 2 - Social + persistence

- chat;
- reactions;
- typing;
- Continue Watching;
- Local Mode;
- disconnect/reconnect polish.

### Phase 3 - Nearby companion

- define bridge protocol;
- mobile discovery/pairing;
- minimal desktop bridge PR if required;
- remote playback controls;
- room/chat/reaction relay.

**Gate:** one phone can pair with and control one Windows desktop reliably.

### Phase 4 - RevenueCat + product polish

- Plus entitlement;
- premium theme/reaction;
- paywall/upgrade UI;
- restore;
- icon;
- animation;
- accessibility/error states.

### Phase 5 - Cast

Only after P0 is stable:

- discovery/device picker;
- Cast playback adapter;
- direct-URL demo;
- sync state feedback.

### Phase 6 - Submission hardening

- clean install test;
- full real-device demo rehearsal;
- README/setup;
- screenshot;
- demo recording;
- submission checklist.

---

## 20. Agent execution rules

For the implementation agent:

### Development environment autonomy

Treat environment setup as part of the implementation task, not as a reason to stop.

- Inspect the current machine/toolchain before changing it.
- If needed, install and configure reputable development tooling such as Android Studio, Android SDK/platform tools, adb, Android Emulator/AVDs, Flutter/Dart tooling, build dependencies, debugging utilities, or other tools required to implement and validate the app.
- Discover and use available skills/tools/plugins when they materially help with implementation, browser work, GitHub, UI inspection, or testing.
- Use an Android emulator for rapid iteration, multiple screen sizes, orientation testing, repeatable UI checks, and visual inspection.
- Use real Android hardware for final validation where network/hardware behavior matters, especially media playback, lifecycle, LAN discovery, Nearby MeowWatch, RevenueCat, and Cast.
- If a preferred emulator/toolchain is unsuitable for the machine, choose a practical alternative rather than abandoning the feature.
- Avoid unrelated software installs, unnecessary system-wide changes, or disabling meaningful security protections.
- Record unusual setup needed for reproducibility.

### Priority semantics

P0/P1/P2 labels describe **implementation order and risk management**, not permission to stop early.

The expected end state is to complete the full practical scope of this spec. Finish P0 and stabilize it first, then continue through P1 and other specified work. A lower-priority feature may remain unfinished only when there is a genuine technical, platform, legal/compliance, dependency, or deadline blocker that cannot reasonably be solved. In that case, implement the best fallback, document the exact blocker, and continue completing everything else.


- Treat this spec as product intent, not a requirement to preserve every suggested internal detail if a materially better implementation is found.
- Make reasonable low-impact implementation decisions autonomously.
- Do not repeatedly stop for approval over ordinary engineering fixes.
- Stop and surface a decision only when:
  - user preference materially changes UX/product direction;
  - a choice is irreversible/high-impact;
  - Shipaton eligibility/compliance is uncertain;
  - a security/privacy issue needs a product tradeoff;
  - a major scope cut is required.
- For every visually important feature, inspect the actually rendered UI on emulator and/or device screenshots before considering it finished; do not judge visual quality from code alone.
- The finished product must feel like a polished Android app: mobile-first, touch-first, coherent Material 3 conventions where useful, MeowWatch's cozy/cinematic identity, strong spacing/typography/hierarchy, good empty/error states, and no generic AI-slop styling.
- Keep commits small and coherent.
- Keep CI green.
- Prefer tests around protocol/state boundaries rather than brittle pixel snapshots.
- Do not introduce a backend unless there is a concrete requirement that cannot be met locally.
- Avoid dependency bloat.
- Clean up temporary processes/services spawned during development (dev servers, watchers, adb helpers, test workers, local bridges) when they are no longer needed; do not kill unrelated shared/active processes.
- If nearby desktop support requires changing `PeterShanxin/MeowWatch`, make it a separate focused PR rather than mixing histories.
- Record material scope changes in this spec or an adjacent decision log.

---

## 21. References

Desktop project:

- `https://github.com/PeterShanxin/MeowWatch`

Useful desktop milestones to inspect:

- v0.10.0-alpha - background updater + chat unread work
- v0.20.0-alpha - presence connect/disconnect/reconnect
- v0.40.0-alpha - generated friendly usernames
- v0.42.0-alpha - fullscreen/player and sync RTT work
- v0.44/v0.45 era - peer URL and webpage/direct-media loading improvements
- v0.47.0-alpha - unified "Load a video" UX
- v0.49.0-alpha - Local Player Mode and related public-release hardening
- v0.50.0-alpha - automatic working public Syncplay endpoint discovery

Current desktop README documents:

- precision sync;
- floating chat;
- reactions/typing;
- themes;
- Continue Watching;
- smart auto-pause;
- local/direct media loading;
- custom Syncplay client;
- Drift/SQLite persistence;
- AGPL-3.0-only licensing.

Shipaton references:

- `https://www.shipaton.com/next-gen`
- `https://www.shipaton.com/faq`
- `https://www.shipaton.com/pt-br/rules`
- `https://www.shipaton.com/blog/how-to-submit-your-app-for-shipaton`

RevenueCat references:

- `https://www.revenuecat.com/docs/getting-started/installation/flutter`
- `https://www.revenuecat.com/docs/tools/paywalls`
- `https://www.revenuecat.com/docs/web/web-billing/web-purchase-links`
