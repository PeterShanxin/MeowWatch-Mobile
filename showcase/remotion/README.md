# MeowWatch launch film

A 70-second product film: one idea per screen, set in type on a warm paper
ground, with real app recordings carrying every functional claim. Each shot of
the app is an unedited 1× excerpt of a real recording and carries a small
label saying what it is. Titles, chat bubbles and the brand sign-off are the
only drawn elements. See [STORYBOARD.md](STORYBOARD.md) for the cut list and
[source-media/README.md](source-media/README.md) for footage provenance.

## Preview

Node 24 is supported. Run `npm ci`, then `python prepare_media.py` to stage the
committed clips, brand mark and fonts in `public/`, and
`python compose_music.py` to generate the soundtrack. `npm run dev` opens the
Studio; composition `MeowWatchLaunch` is 1920 × 1080, 30 fps and 2,100 frames.

`prepare_media.py --recordings <dir>` re-cuts the clips in `source-media/` from
the raw recordings, which are kept outside the repository.

## Export

`npm run render` writes `out/MeowWatch-Mobile-Remotion.mp4`. The **Remotion
submission film** workflow runs the same steps on hosted Ubuntu from the
committed clips and uploads the film with three review stills.

`compose_music.py` creates an original 120 BPM score from synthesized keys,
pads, bass and percussion; it uses no third-party recording, sample or
melody. DM Sans and DM Serif Display keep their bundled SIL Open Font License
notices. The Sintel trailer shown inside the app is © Blender Foundation
(sintel.org), CC BY 3.0, credited in the film's closing frame.
