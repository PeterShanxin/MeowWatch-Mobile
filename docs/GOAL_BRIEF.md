# MeowWatch Mobile - Goal Mode Brief

**Goal mode task:** Build and finish MeowWatch Mobile for Shipaton 2026.

**Primary specification:** `MEOWWATCH_MOBILE_SPEC_v3.md`

## Outcome

Deliver a polished, working, public Android-first **MeowWatch Mobile** product that is genuinely ready to submit to Shipaton 2026 Next Gen.

This is not a planning exercise, prototype, UI mockup, or partial MVP. Continue working until the success criteria below are satisfied or a genuine blocker makes a criterion impossible.

MeowWatch is **couples-first, but not couples-only**. The clearest product story is long-distance movie night, while the same app should work naturally for friends and other small groups.

## Working locations

- Clone/work parent directory: `<CLONE_PARENT_DIRECTORY>`
- Existing desktop MeowWatch reference: `<MEOWWATCH_DESKTOP_REPO_OR_PATH>`
- Target GitHub repository: `PeterShanxin/MeowWatch-Mobile`

Create/configure the GitHub repository yourself if needed.

## Execution autonomy

You may autonomously:

- use the terminal, browser, computer, GitHub, and available connected tools;
- create/clone/configure repositories;
- install/configure reputable Android/Flutter development software needed for the work;
- create Android emulators/AVDs and use adb;
- discover and use relevant skills/tools/plugins;
- make ordinary implementation and product-detail decisions;
- make focused changes/PRs to desktop MeowWatch when Nearby Companion support requires them;
- inspect rendered UI, screenshots, logs, CI, tests, and running apps;
- fix ordinary failures without waiting for approval.

Ask the user only when a blocker genuinely requires:

- credentials, login, 2FA, or manual legal acceptance;
- an irreversible/high-impact product decision not covered by the spec;
- a meaningful Shipaton eligibility/compliance decision;
- a significant security/privacy tradeoff;
- a major scope reduction caused by a real blocker.

Do not stop merely to report a small bug, failed test, missing SDK, dependency issue, emulator problem, or implementation choice. Investigate and resolve those yourself.

## Priority rule

P0/P1/P2 indicate **what to stabilize first**, not what may be omitted.

- Finish P0 first.
- Stabilize it.
- Then continue through P1 and the rest of the practical specified scope.
- Attempt Cast and other P1 work after the core is reliable.
- Leave something unfinished only when there is a real blocker that cannot reasonably be solved. Implement the best fallback, document the blocker precisely, and keep finishing everything else.

## Non-negotiable product requirements

- Android-first mobile-native app, not a resized Windows UI.
- Public `MeowWatch-Mobile` GitHub repository.
- AGPL-3.0-only unless a genuine license conflict requires otherwise.
- Core two-person experience must be excellent.
- Create/join room, secure sync, mobile playback, play/pause/seek synchronization.
- Chat, reactions, typing/presence, reconnect behavior.
- Local Player Mode and Continue Watching.
- Nearby MeowWatch discovery/pairing/companion control.
- RevenueCat implemented as a real product flow.
- Free users can host 1 real Together Session per local calendar day.
- Joining other people's sessions remains free.
- `meowwatch_plus` unlocks unlimited hosting.
- RevenueCat purchase/entitlement/restore flow actually works.
- Cast is implemented if technically feasible after core stability; do not let it break the submission.
- No DRM bypass or protected-streaming circumvention.

## UI / UX quality bar

The final app must look deliberately designed and polished.

- Use good Android-native/touch-first UX.
- Use Material 3 conventions where helpful without producing a generic stock Material demo.
- Preserve MeowWatch's cozy/cinematic personality and restrained cat identity.
- Avoid AI-slop patterns: gratuitous gradients, random glass cards, excessive pills, fake dashboards, cluttered copy, inconsistent visual language.
- Inspect **actual rendered screens** and iterate visually.
- Test at least:
  - a typical Android phone;
  - a small phone;
  - a tablet-sized layout;
  - portrait and landscape where relevant.
- Tablet UX must be intentionally laid out rather than merely stretched.
- Check safe areas, keyboard behavior, clipping, overflow, text scaling, contrast, touch targets, loading/error/empty states, and motion.

## Testing expectations

Use the appropriate combination of:

- unit tests;
- widget tests;
- integration tests;
- emulator testing;
- screenshots/visual QA;
- real-device testing.

Use real Android hardware where it materially matters, especially:

- media playback;
- app lifecycle;
- LAN/Nearby discovery;
- mobile-to-desktop companion mode;
- RevenueCat;
- Cast.

Keep CI green and clean up temporary processes/services/emulators/workers you start when they are no longer needed. Do not kill unrelated active processes.

## Success criteria

Do not consider the goal complete until all practical criteria below are true:

1. A clean checkout can build/install the Android app.
2. The public repo is polished, licensed, documented, and contains no secrets.
3. A first-time user can create or join a room without confusing setup.
4. Two real clients can repeatedly synchronize playback, including play/pause/seek.
5. Chat/reactions/presence work during a real session.
6. Disconnect/reconnect and common lifecycle interruptions recover cleanly.
7. Local Mode and Continue Watching work.
8. A phone can securely discover/pair with and control nearby desktop MeowWatch.
9. RevenueCat purchase -> `meowwatch_plus` entitlement -> unlimited hosting works end-to-end, including restore.
10. Free-host quota semantics work correctly and do not charge reconnects/target changes as new sessions.
11. Important UI has passed visual QA on phone and tablet-sized layouts, portrait/landscape where relevant.
12. Cast works if a technically reliable implementation is feasible; otherwise the exact blocker and fallback are documented without compromising the rest of the product.
13. No obvious placeholder UI, dead-end flows, or silent failure states remain.
14. The full demo path can be rehearsed from a clean install without special manual repair.
15. The project is in a state you would confidently submit to Shipaton.

## Final closeout

Before declaring the goal complete:

1. Run the relevant tests and CI.
2. Perform a clean-install end-to-end rehearsal.
3. Visually inspect the final critical screens.
4. Review the repo for secrets, temporary files, stale debug code, and misleading docs.
5. Verify README/license/setup/submission assets readiness.
6. Summarize:
   - what was completed;
   - tests and real-device checks performed;
   - any genuine remaining blockers;
   - exact repo/PR/release state;
   - the recommended Shipaton demo path.

Do not declare success merely because the code compiles or P0 is implemented.
