# Flutter semantics diagnostic candidate

This is an opt-in diagnostic for Flutter 3.44.0, not an adopted production SDK
patch. [Flutter PR #190431](https://github.com/flutter/flutter/pull/190431) was
still unmerged when pinned at `65e4783d8a1019029da88ee2435892ef638a9937`.
It rebuilds cached semantics fragments when their sibling conflict changes.
The fixed 14-line patch, upstream fixture, license, and source provenance are
checked in here; preparation never downloads or executes a floating PR.

The original upstream fixture failed locally with `!child.attached` on the
unmodified SDK and passed with a copied framework override. This does **not**
prove it fixes the Android `object.dart:6670` geometry assertion. The
[author's scope note](https://github.com/flutter/flutter/issues/189902#issuecomment-5561938282)
also leaves that variant unproven. Semantics and framework assertions stay on.

## Explicit candidate runs

Only the `Android product journey` and `Production phone and tablet journey`
workflows expose `semantics_candidate`, default `false`. Normal PR and default
dispatch runs skip all compatibility steps. Candidate runs use a separate
concurrency group and visibly named job/artifact.

`prepare.py` takes an explicit source SDK path. In a GitHub-hosted Actions
runner it copies the complete SDK with independent files into a new directory
strictly under `RUNNER_TEMP`, verifies the official 3.44.0 revision and exact
source/output hashes, and patches only the copy. It checks that the cached
source file's before/after hashes match. The workflow then explicitly points
`FLUTTER_ROOT` and `PATH` at that copy. The action's original SDK cache remains
unmodified. An interrupted or failed copy is retained in disposable runner
storage; the script never recursively deletes an SDK or reuses an output path.

Before any app build, the candidate workflow runs this upstream regression:

```sh
flutter test --reporter expanded tools/flutter_compat/overlay_sibling_conflict_test.dart
```

The fixture deliberately remains outside ordinary `test/`: it reproduces an
upstream failure on the baseline SDK. Its `ExcludeSemantics` widget belongs to
the upstream trigger and is not an app accessibility workaround.

`build/flutter-compat/` is uploaded even when preparation or the regression
fails. It contains the preparation result, fixed-source provenance, and
regression log; candidate app recordings retain their normal acceptance gates.
A prepared SDK or passing fixture alone is not native acceptance.

## Local checks

Local SDK mutation is not supported. Read-only hash/patch verification is:

```powershell
python tools/flutter_compat/prepare.py --check --source-sdk 'C:/absolute/flutter' --report '.local/verification/semantics-check.json'
python -m unittest discover -s tools/flutter_compat -p 'test_*.py'
```

Both LF and CRLF forms of the exact official source are pinned; the original
line endings are preserved. Other SDK versions, modified/repatched source,
altered patch content, reused destinations, and unsafe runner paths fail.
