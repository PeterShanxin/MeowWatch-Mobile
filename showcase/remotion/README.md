# MeowWatch launch film

The editable Remotion edition uses the same 94-second story and original native
captures as [the documented edit](../../docs/DEMO_SCRIPT.md). Motion, typography,
device framing and an original soundtrack are added around the real app footage.
Paired recordings retain their common approximate clock. No app interactions or
device results are synthesized, sped up or independently retimed.

## Preview

Node 24 is supported. Run `npm ci` here. Download the
`meowwatch-remotion-preview-<attempt>` artifact from **Remotion submission film**
into this directory's `public/` folder, then run `npm run dev`. The Studio opens
at the URL printed by the command; composition `MeowWatchLaunch` is 1920 × 1080,
30 fps and 2,820 frames. Keep playback paused while editing on constrained hosts.

The global `remotion` command is optional; this project's lockfile pins the
renderer and all Remotion packages to 4.0.529 for reproducible output.

## Export

The **Remotion submission film** workflow fetches the existing pinned source
recordings, prepares 1× clips, creates music, checks TypeScript and renders with
two concurrent workers on hosted Ubuntu. It also exports three review stills.
It runs on scoped changes to the showcase branch or manual dispatch. No Android
build or emulator starts in this workflow. The separate normal-APK rehearsal
continues to verify product behavior.

`prepare_media.py` reuses the existing source/timeline validation and only trims
the EDL's selected intervals. `compose_music.py` creates a new 120 BPM electronic
score using synthesized keys, pads, bass and percussion; it uses no third-party
recording, samples or borrowed melody. DM Sans and DM Serif Display retain their
bundled SIL Open Font License notices. Brand and app footage provenance remains
in the main repository's third-party notices. Tool dependencies retain their own
licenses; they are not embedded in the Android product.

The original private YouTube candidate remains available until this edition has
been visually and audibly reviewed. Rendering success does not approve the film
or close physical-device, Nearby, Cast or submission acceptance.
