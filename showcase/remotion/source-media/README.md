# Film source media

Every app shot in the film is an unedited 1× excerpt of a real recording made
on September 26–27, 2026. `prepare_media.py` lists each excerpt's source file,
start time and duration; the raw recordings are kept outside the repository.

- `phone-*.mp4`: MeowWatch Mobile on a physical OnePlus PLK110 (Android 16),
  recorded at 1272 × 2772 with scrcpy screen mirroring, scaled to 720 px wide.
  The status bar uses Android's demo mode (fixed clock, no notifications).
  Purchases use the RevenueCat Test Store; no real charge is made.
- `together-sync.mp4`, `together-react.mp4`: two continuous Windows screen
  recordings showing MeowWatch for Windows `v0.51.0-alpha` and the same phone
  (mirrored with scrcpy) side by side in one Together room. The film crops
  both windows from the same recording, so both sides stay on one clock;
  nothing is re-timed.
- `phone-invite-video.mp4`: a MeowWatch invite link carrying a direct video
  link, opened on the phone while MeowWatch for Windows hosts that room with
  the same video.

The film playing inside MeowWatch is the official Sintel trailer:
**© Blender Foundation | sintel.org**, licensed under
[Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/).
[Original trailer](https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4).
The excerpts, device framing and surrounding titles are edits for this film.
