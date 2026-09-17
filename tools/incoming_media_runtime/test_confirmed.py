import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from tools.android_install.runner import Adb, PACKAGE, RuntimeFailure
from tools.android_native_ui.observer import ObserverIntegrityFailure
from tools.incoming_media_runtime.confirmed import (
    ConfirmedIntake, FIXTURE_URL, MEDIA_COLLECTION, Playback, download_fixture,
    owned_row, playback, require_advance, temporary_read_grant,
)


NAME = 'meowwatch-intake-' + 'a' * 32 + '.mp4'
URI = MEDIA_COLLECTION + '/42'
ROW = f'Row: 0 _id=42, _display_name={NAME}, mime_type=video/mp4'
GRANT = (f'UriPermission{{abcd 0 @ {URI}}}\n'
         f'  targetUserId=0 sourcePkg=com.android.providers.media.module targetPkg={PACKAGE}\n'
         '  mode=0x1 owned=0x1 global=0x0 persistable=0x0 persisted=0x0\n'
         '  readOwners:\n    * owner\n')


def node(label, *, clickable=False, kind='android.widget.TextView', y=0):
    return (f'<node text="{label}" content-desc="" package="{PACKAGE}" class="{kind}" '
            f'enabled="true" visible-to-user="true" clickable="{str(clickable).lower()}" '
            f'bounds="[0,{y}][100,{y + 40}]"/>')


def review(title):
    return '<hierarchy>' + ''.join((node('Open shared video?'), node(title), node('Cancel', clickable=True),
                                   node('Open video', clickable=True, y=200))) + '</hierarchy>'


def player(position=0, *, title='trailer.mp4', playing=True):
    return '<hierarchy>' + ''.join((node(title), node(f'0:{position:02d}'), node('0:52'),
                                   node('', kind='android.widget.SeekBar'),
                                   node('Pause' if playing else 'Play', clickable=True, y=300))) + '</hierarchy>'


class ConfirmedPlaybackTests(unittest.TestCase):
    def test_exact_content_row_rejects_foreign_and_ambiguous_ownership(self):
        self.assertEqual(owned_row(ROW, NAME), URI)
        for value in (ROW + '\n' + ROW, ROW.replace(NAME, 'foreign.mp4'),
                      ROW.replace('video/mp4', 'text/plain'), 'No result found.'):
            with self.subTest(value=value), self.assertRaises(RuntimeFailure):
                owned_row(value, NAME)

    def test_actual_grant_requires_exact_uri_target_and_only_temporary_read(self):
        report = temporary_read_grant(GRANT, URI)
        self.assertTrue(report['readGranted'])
        self.assertFalse(report['persisted'])
        for changed in (GRANT.replace(URI, URI + '0'), GRANT.replace(PACKAGE, 'other.app'),
                        GRANT.replace('persisted=0x0', 'persisted=0x1'),
                        GRANT.replace('mode=0x1', 'mode=0x3'),
                        GRANT.replace('persistable=0x0', 'persistable=0x1'),
                        GRANT.replace('owned=0x1', 'owned=0x0'), GRANT + GRANT):
            with self.subTest(changed=changed), self.assertRaises(RuntimeFailure):
                temporary_read_grant(changed, URI)

    def test_player_requires_real_source_timeline_duration_and_progress(self):
        before, after = playback(player(1), 'trailer.mp4'), playback(player(4), 'trailer.mp4')
        self.assertEqual(require_advance(before, after), 3)
        for xml in (review('trailer.mp4'), player().replace('0:52', '0:04'),
                    player().replace('SeekBar', 'TextView'), player(title='other.mp4')):
            with self.subTest(xml=xml), self.assertRaises(RuntimeFailure):
                playback(xml, 'trailer.mp4')
        for invalid in (before, Playback(4, 52, False), Playback(4, 90, True)):
            with self.subTest(invalid=invalid), self.assertRaises(RuntimeFailure):
                require_advance(before, invalid)

    def test_fixed_public_download_refuses_changed_bytes_and_redirects(self):
        for url in (FIXTURE_URL, 'https://other.example/video.mp4'):
            response = Mock()
            response.geturl.return_value = url
            response.read.return_value = b'changed fixture'
            response.__enter__ = Mock(return_value=response)
            response.__exit__ = Mock(return_value=False)
            with patch('tools.incoming_media_runtime.confirmed.urllib.request.urlopen', return_value=response) as opened:
                with self.assertRaises(RuntimeFailure):
                    download_fixture()
                self.assertEqual(opened.call_args.args, (FIXTURE_URL,))

    def test_https_confirmation_drives_open_then_play_and_observes_native_progress(self):
        with tempfile.TemporaryDirectory() as temporary:
            adb = Adb('emulator-5554', 'confirmed-test')
            runner = ConfirmedIntake(adb, Path(temporary))
            runner.observer.production_pid = Mock(return_value='123')
            observations = [review('trailer.mp4'), review('trailer.mp4'), player(0, playing=False), player(1), player(4)]
            runner.observe = Mock(side_effect=observations)
            with patch.object(adb, 'run', return_value=subprocess.CompletedProcess(
                [], 0, f'Status: ok\nActivity: {PACKAGE}/.MainActivity\n'.encode(), b''
            )) as command, patch.object(adb, 'screenshot', return_value=b'evidence'), patch(
                'tools.incoming_media_runtime.confirmed.time.sleep'
            ):
                result = runner.accept_video(content=False)
            self.assertEqual(result['advanceSeconds'], 3)
            self.assertTrue(result['openActionInvoked'])
            taps = [call.args for call in command.call_args_list if call.args[:3] == ('shell', 'input', 'tap')]
            self.assertEqual(taps, [('shell', 'input', 'tap', '50', '220'),
                                    ('shell', 'input', 'tap', '50', '320'),
                                    ('shell', 'input', 'tap', '50', '320')])
            self.assertEqual(runner.observe.call_count, 5)
            self.assertTrue((Path(temporary) / 'confirmed-https-share-advanced.xml').is_file())

    def test_observer_integrity_failure_is_never_retried_as_loading(self):
        with tempfile.TemporaryDirectory() as temporary:
            runner = ConfirmedIntake(Adb('emulator-5554', 'confirmed-test'), Path(temporary))
            runner.observe = Mock(side_effect=ObserverIntegrityFailure('PID changed'))
            with self.assertRaises(ObserverIntegrityFailure):
                runner.wait('test', lambda value: None)
            runner.observe.assert_called_once()

    def test_content_open_requires_observed_grant_before_any_confirmation_tap(self):
        warning = 'This app granted temporary video access. To keep it in Continue Watching, choose it again using Open a video.'
        for grant, succeeds in ((GRANT, True), ('no grants', False)):
            with self.subTest(grant=grant), tempfile.TemporaryDirectory() as temporary:
                adb = Adb('emulator-5554', 'confirmed-test')
                runner = ConfirmedIntake(adb, Path(temporary))
                runner.uri = URI
                runner.observer.production_pid = Mock(return_value='123')
                confirmation = review('Shared video').replace('</hierarchy>', node(warning) + '</hierarchy>')
                runner.observe = Mock(side_effect=[confirmation, confirmation,
                    player(0, title='Shared video', playing=False),
                    player(1, title='Shared video'), player(4, title='Shared video')])
                def run(*args, **kwargs):
                    output = grant if args[:3] == ('shell', 'dumpsys', 'activity') else f'Status: ok\nActivity: {PACKAGE}/.MainActivity\n'
                    return subprocess.CompletedProcess(args, 0, output.encode(), b'')
                with patch.object(adb, 'run', side_effect=run) as command, patch.object(
                    adb, 'screenshot', return_value=b'evidence'
                ), patch('tools.incoming_media_runtime.confirmed.time.sleep'):
                    if succeeds:
                        result = runner.accept_video(content=True)
                        self.assertTrue(result['temporaryReadGrant']['readGranted'])
                        self.assertEqual(result['advanceSeconds'], 3)
                    else:
                        with self.assertRaises(RuntimeFailure):
                            runner.accept_video(content=True)
                        self.assertFalse(any(call.args[:3] == ('shell', 'input', 'tap') for call in command.call_args_list))
                self.assertIn('--grant-read-uri-permission', command.call_args_list[0].args)

    def test_provider_fixture_is_written_as_bytes_and_read_back_before_delivery(self):
        data = b'controlled media bytes'
        digest = hashlib.sha256(data).hexdigest()
        with tempfile.TemporaryDirectory() as temporary:
            adb = Adb('emulator-5554', 'confirmed-test')
            runner = ConfirmedIntake(adb, Path(temporary))
            runner.name = NAME
            runner.query = Mock(side_effect=['No result found.', ROW])
            with patch('tools.incoming_media_runtime.confirmed.download_fixture', return_value=data), patch(
                'tools.incoming_media_runtime.confirmed.FIXTURE_SHA256', digest
            ), patch('tools.incoming_media_runtime.confirmed.subprocess.run', return_value=subprocess.CompletedProcess([], 0, b'', b'')) as write, patch.object(
                adb, 'run', return_value=subprocess.CompletedProcess([], 0, data, b'')
            ) as command:
                result = runner.prepare_video()
            self.assertEqual(write.call_args.kwargs['input'], data)
            self.assertEqual(write.call_args.args[0][-5:], ['-T', 'content', 'write', '--uri', URI])
            self.assertEqual(command.call_args.args, ('exec-out', 'content', 'read', '--uri', URI))
            self.assertEqual(result['providerReadbackSha256'], digest)

    def test_uncertain_row_owner_is_retained_without_any_delete(self):
        with tempfile.TemporaryDirectory() as temporary:
            adb = Adb('emulator-5554', 'confirmed-test')
            runner = ConfirmedIntake(adb, Path(temporary))
            runner.name, runner.uri = NAME, URI
            runner.query = Mock(return_value=ROW.replace(NAME, 'foreign.mp4'))
            runner.observer.cleanup = Mock()
            with patch.object(adb, 'run') as command:
                with self.assertRaisesRegex(RuntimeFailure, 'cleanup'):
                    runner.cleanup()
            command.assert_not_called()
            report = json.loads((Path(temporary) / 'confirmed-cleanup.json').read_text())
            self.assertEqual(report['mediaStoreRow'], 'retained-owner-or-cleanup-unconfirmed')
            self.assertFalse(report['completed'])

    def test_owned_row_cleanup_deletes_only_its_exact_uri_and_checks_absence(self):
        with tempfile.TemporaryDirectory() as temporary:
            adb = Adb('emulator-5554', 'confirmed-test')
            runner = ConfirmedIntake(adb, Path(temporary))
            runner.name, runner.uri = NAME, URI
            runner.query = Mock(side_effect=[ROW, 'No result found.'])
            runner.observer.cleanup = Mock()
            with patch.object(adb, 'run') as command:
                runner.cleanup()
            command.assert_called_once_with('shell', 'content', 'delete', '--uri', URI)
            self.assertEqual(runner.cleanup_result['mediaStoreRow'], 'removed')

    def test_playback_success_cannot_pass_when_owned_fixture_cleanup_fails(self):
        for deletion_error in (None, RuntimeFailure('provider unavailable')):
            with self.subTest(deletion_error=deletion_error), tempfile.TemporaryDirectory() as temporary:
                adb = Adb('emulator-5554', 'confirmed-test')
                runner = ConfirmedIntake(adb, Path(temporary))
                runner.name, runner.uri = NAME, URI
                runner.query = Mock(return_value=ROW)
                runner.prepare_video = Mock(return_value={'sha256': 'fixture'})
                runner.accept_video = Mock(return_value={'advanceSeconds': 3})
                runner.observer.install = Mock(return_value={})
                runner.observer.cleanup = Mock()
                with patch.object(adb, 'run', side_effect=deletion_error):
                    with self.assertRaisesRegex(RuntimeFailure, 'cleanup'):
                        runner.run()
                report = json.loads((Path(temporary) / 'confirmed-result.json').read_text())
                self.assertEqual(len(report['cases']), 2)
                self.assertFalse(report['completed'])
                self.assertIn('cleanupFailure', report)
                self.assertEqual(report['cleanup']['mediaStoreRow'],
                                 'retained-owner-or-cleanup-unconfirmed')
                runner.observer.cleanup.assert_called_once()

    def test_final_success_requires_confirmed_fixture_and_observer_cleanup(self):
        for observer_error in (None, RuntimeFailure('observer uninstall failed')):
            with self.subTest(observer_error=observer_error), tempfile.TemporaryDirectory() as temporary:
                adb = Adb('emulator-5554', 'confirmed-test')
                runner = ConfirmedIntake(adb, Path(temporary))
                runner.name, runner.uri = NAME, URI
                runner.query = Mock(side_effect=[ROW, 'No result found.'])
                runner.prepare_video = Mock(return_value={})
                runner.accept_video = Mock(return_value={'advanceSeconds': 3})
                runner.observer.install = Mock(return_value={})
                runner.observer.cleanup = Mock(side_effect=observer_error)
                with patch.object(adb, 'run'):
                    if observer_error is None:
                        runner.run()
                    else:
                        with self.assertRaises(RuntimeFailure):
                            runner.run()
                report = json.loads((Path(temporary) / 'confirmed-result.json').read_text())
                self.assertEqual(report['completed'], observer_error is None)
                self.assertEqual(report['cleanup']['mediaStoreRow'], 'removed')
                self.assertEqual(report['cleanup']['completed'], observer_error is None)

    def test_unconfirmed_insertion_is_retained_and_fails_cleanup_without_delete(self):
        with tempfile.TemporaryDirectory() as temporary:
            adb = Adb('emulator-5554', 'confirmed-test')
            runner = ConfirmedIntake(adb, Path(temporary))
            runner.cleanup_result['mediaStoreRow'] = 'retained-ownership-unconfirmed'
            runner.observer.cleanup = Mock()
            with patch.object(adb, 'run') as command:
                with self.assertRaisesRegex(RuntimeFailure, 'cleanup'):
                    runner.cleanup()
            command.assert_not_called()
            report = json.loads((Path(temporary) / 'confirmed-cleanup.json').read_text())
            self.assertFalse(report['completed'])
            self.assertEqual(report['mediaStoreRow'], 'retained-ownership-unconfirmed')


if __name__ == '__main__':
    unittest.main()
