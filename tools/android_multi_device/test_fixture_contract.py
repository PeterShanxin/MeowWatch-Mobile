"""Exercise real fixture-copy and CI preflight code without media or Android tools."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
BASH = ('C:/Program Files/Git/bin/bash.exe' if os.name == 'nt'
        and Path('C:/Program Files/Git/bin/bash.exe').is_file() else shutil.which('bash'))
CANONICAL_URL = 'http://10.0.2.2:18765/sync-fixture.mp4'
ALIAS_URL = 'http://10.0.2.2:18765/Bee.mp4'
FIXTURE_BYTES = b'fixture contract bytes\x00\xff\n'


@unittest.skipUnless(BASH, 'Bash is required to exercise the fixture scripts')
class FixtureContractTests(unittest.TestCase):
    def test_preparation_copies_exact_bytes_and_records_both_hashes(self):
        source = (ROOT / 'tools/android_multi_device/prepare_fixture.sh').read_text(encoding='utf-8')
        marker = 'recording_alias="$output_dir/Bee.mp4"\n'
        self.assertEqual(source.count(marker), 1)
        # Execute the actual post-generation copy/hash block. Download, source
        # integrity and FFmpeg duration validation belong to the native job.
        block = marker + source.split(marker, 1)[1].split('ffprobe -v error', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            canonical = root / 'sync-fixture.mp4'
            canonical.write_bytes(FIXTURE_BYTES)
            original = root / 'bee-source.mp4'
            original.write_bytes(b'original source contract bytes')
            script = root / 'copy.sh'
            script.write_text('''#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
output_dir="$PWD"
fixture_file="$output_dir/sync-fixture.mp4"
source_file="$output_dir/bee-source.mp4"
''' + block, encoding='utf-8', newline='\n')
            result = subprocess.run([BASH, script.as_posix()], cwd=root,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(canonical.read_bytes(), FIXTURE_BYTES)
            self.assertEqual((root / 'Bee.mp4').read_bytes(), FIXTURE_BYTES)
            self.assertEqual(original.read_bytes(), b'original source contract bytes')
            expected_hash = hashlib.sha256(FIXTURE_BYTES).hexdigest()
            for name in ('sync-fixture.mp4', 'Bee.mp4'):
                with self.subTest(name=name):
                    recorded = (root / f'{name}.sha256').read_text().split()[0]
                    self.assertEqual(recorded, expected_hash)

    def run_preflight(self, video_url, *, production=True, alias=FIXTURE_BYTES):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = root / 'build/android-multi-device'
            fixture = runtime / 'fixture'
            apks = runtime / 'apks'
            sessions = runtime / 'sessions'
            for path in (fixture, apks, sessions):
                path.mkdir(parents=True)
            (fixture / 'sync-fixture.mp4').write_bytes(FIXTURE_BYTES)
            if alias is not None:
                (fixture / 'Bee.mp4').write_bytes(alias)
            for role in ('host', 'guest'):
                (apks / f'{role}.apk').write_bytes(b'preflight placeholder, never installed')
            target = ('integration_test/production_together_test.dart' if production
                      else 'integration_test/together_smoke_test.dart')
            (apks / 'build-provenance.tsv').write_text(
                f'room\tfixture-contract\nserver\tsyncplay.pl\nport\t8995\n'
                f'target\t{target}\nvideo_url\t{video_url}\n'
                'coordination_url\thttp://10.0.2.2:18766/invite\n', encoding='utf-8')
            # The next preflight gate stops an accepted URL before any server,
            # emulator or external media tool can start.
            (sessions / 'stop-before-launch').write_text('contract sentinel', encoding='utf-8')
            command = [BASH, (ROOT / 'tools/android_multi_device/ci_together.sh').as_posix()]
            if production:
                command.append('--production-ui')
            result = subprocess.run(command, cwd=root, capture_output=True,
                                    text=True, timeout=10)
            self.assertEqual(result.returncode, 3, result.stderr)
            self.assertFalse((runtime / 'fixture-server').exists())
            self.assertFalse((runtime / 'ci-result.tsv').exists())
            return result.stderr

    def test_canonical_fixture_remains_allowed_for_both_targets(self):
        for production in (False, True):
            with self.subTest(production=production):
                self.assertIn('AVD session output must be empty',
                              self.run_preflight(CANONICAL_URL, production=production, alias=None))

    def test_identical_alias_is_allowed_only_for_production_ui(self):
        self.assertIn('AVD session output must be empty', self.run_preflight(ALIAS_URL))
        self.assertIn('does not match the scoped fixture',
                      self.run_preflight(ALIAS_URL, production=False))

    def test_alias_missing_empty_or_changed_fails_before_launch(self):
        for alias in (None, b'', b'different bytes'):
            with self.subTest(alias=alias):
                self.assertIn('must be a byte-identical copy',
                              self.run_preflight(ALIAS_URL, alias=alias))

    def test_external_or_unscoped_addresses_are_rejected(self):
        rejected = (
            'http://example.com:18765/Bee.mp4',
            'http://10.0.2.2.example.com:18765/Bee.mp4',
            'http://10.0.2.2:18765@example.com/Bee.mp4',
            'http://127.0.0.1:18765/Bee.mp4',
            'http://10.0.2.2:18766/Bee.mp4',
            'https://10.0.2.2:18765/Bee.mp4',
            'http://10.0.2.2:18765/other.mp4',
            'http://10.0.2.2:18765/../Bee.mp4',
            'http://10.0.2.2:18765/%42ee.mp4',
            'http://10.0.2.2:18765/Bee.mp4?redirect=elsewhere',
            'http://10.0.2.2:18765/Bee.mp4#fragment',
        )
        for video_url in rejected:
            with self.subTest(video_url=video_url):
                self.assertIn('does not match the scoped fixture',
                              self.run_preflight(video_url))


if __name__ == '__main__':
    unittest.main()
