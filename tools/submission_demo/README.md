# Submission demo compositor

Python standard library + the already installed `ffmpeg` and `ffprobe` compose
original recordings into a silent 1920 × 1080 H.264 film at 30 fps. Device footage
stays at 1× speed. The tool adds the selected A / Balanced cat/play logo, bundled
DM Sans / DM Serif Display fonts, navy/cream/blue framing, and text **outside**
device content. It proportionally scales the complete capture; no cropping,
app-pixel replacement, generated motion, zooms, transitions or frozen padding.
Compositing uses RGB and one consistent limited-range BT.709 delivery conversion,
so graphics and native shots do not switch color metadata at editorial cuts.

This tool performs an edit, not product acceptance. It cannot determine whether
an input is authentic, whether the recorded build passed, or whether a claim is
true. Inspect native evidence and the final film before publishing. The output
manifest explicitly leaves those decisions external.

## Author and render

Work from a copy of [example.edl.json](example.edl.json) beside the final evidence
package. Its placeholder paths, hashes, dimensions and timecodes deliberately
do not pass validation. They are schema examples, not known-good footage.

```powershell
python tools/submission_demo/compose.py inspect path/to/phone-000.mp4 path/to/tablet-000.mp4
Get-FileHash path/to/framed-timeline.mp4.manifest.json -Algorithm SHA256
python tools/submission_demo/compose.py validate path/to/final.edl.json
python tools/submission_demo/compose.py render path/to/final.edl.json path/to/meowwatch-mobile-110s.mp4
```

`inspect` supplies each video's actual dimensions, duration and lowercase
SHA256. `Get-FileHash` may print uppercase; lowercase the value in the EDL.
Paths in the EDL resolve relative to that EDL file, including paths to timing
manifests. The bundled brand assets resolve relative to this repository. Use
`--ffmpeg PATH --ffprobe PATH` **before** the subcommand to select executables.
`render ... --preset fast` is available for a quicker local inspection export;
the default preset is `medium`, CRF 19, with at most two encoder threads.

Rendering creates these new files and refuses to overwrite any existing one:

- `film.mp4`: final composition, silent, `yuv420p`, fast-start MP4.
- `film.mp4.edl.json`: exact logical EDL snapshot.
- `film.mp4.manifest.json`: actual input/output SHA256 hashes, source probes,
  source run/commit/runtime metadata, resolved source and output timecodes,
  bundled asset hashes, encoder version and full output probe.
- `film.mp4.sha256`: output checksum.

All pinned inputs are hashed before and after rendering. Source recordings,
timing evidence and the EDL are never modified. Intermediate encodes are kept
inside an owned temporary directory beside the output and removed afterward.
Choose a new output name for revisions. Keep original recordings and their
timing evidence with the film; the manifest is a ledger, not a footage archive.

## EDL contract

`schema_version` is `1`. `purpose` is `submission-edit` for actual native
footage or `synthetic-smoke` for disposable renderer tests. Each source needs
`path`, fixed `sha256`, actual `width`/`height`, `kind`, `runtime`, `run` and
`commit` (full lowercase Git SHA for native footage). Native sources use `kind: native-recording`; synthetic mode accepts
only `kind: synthetic-fixture`. Synthetic mode burns **SYNTHETIC TEST FIXTURE /
NOT APP EVIDENCE** on every frame and records that status in its manifest.
Changing only its purpose cannot promote a smoke EDL into a submission edit.
As with any local editor, manually falsified provenance cannot be detected.

Every shot needs a unique `id`, `kind`, `title` and `caption`:

| Kind | Additional fields | Meaning |
| --- | --- | --- |
| `card` | `duration` | Branded static title/end graphic; identified as graphics in the EDL and manifest. |
| `single` | `source`, `device`, `in`, `out`, `speed: 1`, `label`, optional `disclosure` | One original segment; `device` is portrait `phone` or landscape `tablet`; source seconds count from the recording's first video PTS. |
| `pair` | `timeline`, `phone`, `tablet`, `in`, `out`, `speed: 1`, `phone_label`, `tablet_label`, optional `disclosure` | Two original segments from one run/build; in/out is **one shared estimated timeline interval**, never independent device timecodes. |

Shots appear in array order with direct cuts. Every duration must be a whole
number of 30 fps frames; the entire film must be strictly below 120 seconds.
Use 110 seconds for the current demo plan. A single shot can last at most
60 seconds. Unsupported shot fields, acceleration, missing files, hash mismatch,
unexpected dimensions, rotated metadata, non-square pixels, invalid source
ranges, unused sources, mismatched paired runs/builds and duplicate paired
recordings fail validation.

Keep captions short. Single-phone copy wraps into at most three lines; paired
copy fits two lines. Runtime metadata is always visible. Put additional facts
such as `RevenueCat Test Store / sandbox purchase` in `disclosure`; never call
Test Store a production payment or an emulator physical hardware. Use clear
cuts between separate sessions and recordings. Do not describe the single
Android purchase take's headless protocol peer as a filmed tablet.

### Paired timeline evidence

The `timelines` map references a **pinned schema-v2 or schema-v3 manifest** from
`tools/android_multi_device/compose_side_by_side.py`, which already preserves
raw ADB screenrecord segment start timestamps and missing intervals. The editor
uses its segment SHA256 + original basename to locate each role's actual
recording and derives:

```text
local source in = common shot in - estimated segment start
local source out = local source in + common shot duration
```

Both selected source segments must cover the complete common window. The edit
rejects a window crossing a gap, segment boundary, overlap takeover, unavailable
segment or short tail. Split at an honest editorial cut or choose a continuous
covered interval; do not concatenate native files and hide the lost time.
For a proof action spanning a recording gap, recapture the action.

ADB command timestamps only approximate first-frame alignment. Paired shots
use a concise footer, for example **Android emulators · approximate recording
alignment · 1×**. Visual alignment
does not replace native convergence measurements. The compositor does not
independently shift devices to make them appear synchronized.

Android screenrecord can use a variable frame rate. Cuts retain the frame
already on screen at the requested source time, including when its timestamp
precedes the cut. The renderer shifts the source clock by the requested in point,
then samples it on the 30 fps canvas. A change first appears on the first output
tick at or after its original time; no future frame is selected early. It does
not trim away held frames and rebase the next retained frame to zero. This uses
FFmpeg's [timestamp-based frame synchronization](https://ffmpeg.org/ffmpeg-filters.html#Options-for-filters-with-several-inputs-framesync).
Output ranges must still fit actual video coverage, and source EOF is never
extended to fill a missing tail.

The timing manifest may contain the runner's original Linux paths; matching by
hash and basename lets downloaded artifacts resolve locally without rewriting
that evidence. EDL source paths always point to the downloaded originals.

## Validation and disposable smoke render

```powershell
python -m unittest tools.submission_demo.test_compose -v
python -m py_compile tools/submission_demo/compose.py tools/submission_demo/test_compose.py
```

The test suite creates explicit red/green/blue synthetic fixtures in a temporary
folder, renders title/pair/single/end shots, probes the MP4, and samples output
pixels to check that the measured half-second tablet offset is retained. It
also encodes a true VFR fixture at irregular timestamps 0, 0.7, 1.8, 2.05 and
2.9 seconds. Every rendered frame is checked against the original held-frame
clock for cuts between source frames, a fractional 0.37-second tablet offset
and a clip ending inside the last frame's real coverage. It
checks original source hashes remain unchanged and verifies failure behavior
for falsified dimensions/hashes, gaps, independent retiming, source overrun,
overlong films, mixing synthetic/native purposes and output overwrite.
The fixtures and generated video are deleted when the test finishes. No native
acceptance claim or final demo is produced by running tests.

The submission screenshot remains a separate, original **1179 × 2556** PNG
without a frame. Never extract/upscale this 1080p film to create that required
screenshot. Final native footage and its authored 110-second EDL are intentionally
not bundled in this tool directory.
