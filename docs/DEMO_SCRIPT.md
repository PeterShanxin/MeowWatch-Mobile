# MeowWatch Mobile — submission film

A **70-second product film**. Every functional claim is carried by a real,
unedited 1× recording of the app; titles, the opening chat bubbles and the
brand sign-off are the only drawn elements. Each app shot carries a small
source label. The editable [Remotion project](../showcase/remotion/README.md),
[storyboard](../showcase/remotion/STORYBOARD.md) and
[footage provenance](../showcase/remotion/source-media/README.md) hold the
details.

## Story

| Film time | What the viewer sees | Footage |
| --- | --- | --- |
| 0–5.5 | The long-distance “3, 2, 1… play” countdown falling apart in chat. | Drawn |
| 5.5–9 | Movie night, even miles apart. | Drawn |
| 9–17 | Start a room; send the invite as a QR code. | Physical phone |
| 17–23 | An invite link opens; the join sheet names the video; the room opens on it. | Physical phone |
| 23–38 | MeowWatch for Windows and the phone in one room: play on the phone, pause on the laptop, skip ahead — both follow. | One real-time screen recording |
| 38–46 | Reactions from the phone float up on both screens. | One real-time screen recording |
| 46–50 | Continue Watching. | Physical phone |
| 50–63 | Guests join free; hosts get one free movie night a day; paywall, Test Store purchase, Plus theme. | Physical phone, Test Store, no charge |
| 63–70 | Brand ending with the Sintel credit. | Drawn |

## Sources

- Phone: OnePlus PLK110, Android 16, MeowWatch Mobile Test Store debug build
  (`0.1.1` for the invite-with-video shot), mirrored and recorded with scrcpy.
- Desktop: MeowWatch for Windows `v0.51.0-alpha` hosting the room on the public
  Syncplay server, recorded together with the phone mirror in one Windows
  screen capture.
- Sintel is © Blender Foundation (sintel.org), CC BY 3.0. DM Sans and DM Serif
  Display include their OFL notices. The music is an original synthesized
  120 BPM score. See [third-party notices](../THIRD_PARTY_NOTICES.md).

## Rendering

`npm run render` in `showcase/remotion`, or the **Remotion submission film**
workflow, exports 1920 × 1080 H.264/AAC at 30 fps (2,100 frames). Keep the
runtime, labels, credits and public visibility consistent with
[submission requirements](SUBMISSION_REQUIREMENTS.md).
