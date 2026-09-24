# Review existing native recordings

Dispatch `native-recording-review.yml` with a completed source run and `kind`
(`fullscreen` or `together`). Extraction runs on hosted CI without starting
Android. The local review workflow needs only the resulting PNGs and JSON.

Fullscreen review verifies capture hashes and extracts five indexed original
frames per long clip, or every frame for clips with at most sixteen pictures.
Together review verifies every original segment against the composition
manifest, strictly decodes it, and measures the native variable picture clock.
It retains seven distributed source frames and both pictures around the longest
gap (at most nine PNGs per segment). Frame timestamps, counts, hashes and gap
statistics are exported alongside each result.

Images preserve the original decoded pixels and source time base. No scaling,
interpolation, retiming or repeated-frame padding is applied. Per-device PTS do
not establish exact inter-device alignment, physical-device behavior or visual
acceptance. Inspect the output and record the review separately; generated
receipts deliberately leave `visualReview` pending.

Lightweight timing contracts: `python -m unittest discover -s tools/native_recording_review -p 'test_*.py'`.
