# MeowWatch launch film

The editable Remotion edition is a 94-second story combining app-based UI
animation and real app captures. The Start, Join, playback-control and Chat
chapters recreate the current Flutter layouts in React so the tap and its
result can be seen smoothly. Each is labeled “UI animation · based on the app”
in the film. These scenes explain the product; they are not runtime or paired
device proof. The connected-screen lines are a story motif, not a measured
sync signal. The recreated room and chat copy comes from the app and the
recorded test journey; no extra product capability is implied.

One persistent phone/tablet stage connects the chapters through short camera
moves followed by still holds. Titles and devices leave by moving offscreen.
The outer film stays deep navy with cream titles, blue action labels and peach
accents. Small translucent touch indicators mark each tap without covering
the interface. The media clips are still separate edited sources.
Essential type uses solid readable colors; lower-contrast lines are decorative.

Real footage documents Local Player Mode and fullscreen playback on a physical
OnePlus, Continue Watching on an Android emulator, and the RevenueCat Test
Store purchase, restore and Plus features on an Android emulator. The
physical-phone scenes are separate journeys; they do not depict paired sync
or a purchase on that phone. Capture scenes are played at 1× without synthetic
app states. The physical portrait clip is 10 seconds of the 105–115 second
interval from `02-local-playback.mp4`; the physical landscape clip is seven
seconds from 29–36 seconds in `03-landscape.mp4`. The raw onboarding recording
is not used.

## Preview

Node 24 is supported. Run `npm ci` here. Download the
`meowwatch-remotion-preview-<attempt>` artifact from **Remotion submission film**
into this directory's `public/` folder, then run `npm run dev`. The Studio opens
at the URL printed by the command; composition `MeowWatchLaunch` is 1920 × 1080,
30 fps and 2,820 frames. The two physical clips belong at
`public/media/physical-local-phone.mp4` and
`public/media/physical-fullscreen-phone.mp4`. Keep playback paused while editing
on constrained hosts.

The global `remotion` command is optional; this project's lockfile pins the
renderer and all Remotion packages to 4.0.529 for reproducible output.

The UI animation uses `public/media/bee-still.jpg`, a crop of the Bee playback
image in the existing source capture. The film also requires the prepared
footage in `public/media/`, the brand SVG, two bundled fonts and the generated
soundtrack. See [STORYBOARD.md](STORYBOARD.md) for timing and source boundaries.

## Export

The **Remotion submission film** workflow fetches the existing pinned source
recordings, stages the physical excerpts, prepares 1× clips, creates music,
checks TypeScript and renders with
two concurrent workers on hosted Ubuntu. It also exports three review stills.
It runs on scoped changes to the showcase branch or manual dispatch. No Android
build or emulator starts in this workflow. The separate normal-APK rehearsal
continues to verify product behavior.

`prepare_media.py` reuses the existing source/timeline validation for the
original emulator excerpts. `compose_music.py` creates a 120 BPM electronic
score using synthesized keys, pads, bass and percussion; it uses no third-party
recording, samples or borrowed melody. DM Sans and DM Serif Display retain their
bundled SIL Open Font License notices. Brand and app footage provenance remains
in the main repository's third-party notices. Tool dependencies retain their own
licenses; they are not embedded in the Android product.

The original private YouTube candidate remains available until this edition has
been visually and audibly reviewed. Rendering success does not approve the film
or close physical-device, Nearby, Cast or submission acceptance.
