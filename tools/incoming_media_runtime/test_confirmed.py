import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
import xml.etree.ElementTree as ET

from tools.android_install.runner import Adb, PACKAGE, RuntimeFailure
from tools.android_native_ui.observer import ObserverIntegrityFailure
from tools.incoming_media_runtime.confirmed import (
    ConfirmedIntake, FIXTURE_URL, MEDIA_COLLECTION, Playback, download_fixture,
    owned_backing_file, owned_row, playback, require_advance, temporary_read_grant,
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
    body = node('', kind='android.view.View').replace('/>', '>') + ''.join((
        node(title), node('Playing on this phone'))) + '</node>'
    return '<hierarchy>' + ''.join((node(title), body, node(f'0:{position:02d}'), node('0:52'),
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

    def test_native_tree_accepts_repeated_header_but_requires_exact_body_source(self):
        fixture = Path(__file__).with_name('fixtures') / 'native-api35-paused-player.xml'
        original = fixture.read_text(encoding='utf-8')
        # This is the captured earlier native tree with the current product's
        # header text substituted explicitly, not a new runtime capture.
        current = original.replace('Your own screening', 'trailer.mp4')
        self.assertEqual(current.count('content-desc="trailer.mp4"'), 2)
        self.assertEqual(playback(current, 'trailer.mp4'), Playback(0, 52, False))
        for mutation in ('missing-body', 'wrong-body', 'hidden-body', 'foreign-body',
                         'duplicated-body', 'different-target', 'missing-timeline', 'duplicate-control'):
            with self.subTest(mutation=mutation):
                tree = ET.fromstring(current)
                titles = [n for n in tree.iter('node') if n.get('content-desc') == 'trailer.mp4']
                body = titles[1]
                parent = next(n for n in tree.iter('node') if body in list(n))
                if mutation == 'missing-body':
                    parent.remove(body)
                elif mutation == 'wrong-body':
                    body.set('content-desc', 'other.mp4')
                elif mutation == 'hidden-body':
                    body.set('visible-to-user', 'false')
                elif mutation == 'foreign-body':
                    body.set('package', 'other.app')
                elif mutation == 'duplicated-body':
                    parent.insert(list(parent).index(body), ET.fromstring(ET.tostring(body)))
                elif mutation == 'different-target':
                    next(n for n in tree.iter('node') if n.get('content-desc') ==
                         'Playing on this phone').set('content-desc', 'Playing on nearby desktop')
                elif mutation == 'missing-timeline':
                    next(n for n in tree.iter('node') if n.get('class') ==
                         'android.widget.SeekBar').set('class', 'android.view.View')
                else:
                    control = next(n for n in tree.iter('node') if n.get('content-desc') == 'Play')
                    tree.append(ET.fromstring(ET.tostring(control)))
                with self.assertRaises(RuntimeFailure):
                    playback(ET.tostring(tree, encoding='unicode'), 'trailer.mp4')

    def test_rejected_complete_capture_is_retained_without_reusing_it_on_capture_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            runner = ConfirmedIntake(Adb('emulator-5554', 'confirmed-test'), Path(temporary))
            rejected = player(title='other.mp4')
            runner.observe = Mock(side_effect=[rejected, RuntimeFailure('root unavailable')])
            with patch('tools.incoming_media_runtime.confirmed.time.monotonic', side_effect=[0, 0, 1, 46]), patch(
                'tools.incoming_media_runtime.confirmed.time.sleep'
            ), self.assertRaisesRegex(RuntimeFailure, 'timed out'):
                runner.wait('loaded', lambda value: playback(value, 'trailer.mp4'))
            self.assertEqual((Path(temporary) / 'loaded-last-rejected.xml').read_text(), rejected)
            attempts = json.loads((Path(temporary) / 'loaded-wait.json').read_text())['attempts']
            self.assertEqual(attempts[0]['rejectedXmlSha256'], hashlib.sha256(rejected.encode()).hexdigest())
            self.assertNotIn('rejectedXmlSha256', attempts[1])
            self.assertFalse((Path(temporary) / 'loaded.xml').exists())

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

    def test_held_review_requires_a_new_complete_snapshot_after_transient_capture_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            adb = Adb('emulator-5554', 'confirmed-test')
            runner = ConfirmedIntake(adb, Path(temporary))
            runner.observer.production_pid = Mock(return_value='123')
            runner.observe = Mock(side_effect=[review('trailer.mp4'),
                RuntimeFailure('native observer could not capture a complete active-window hierarchy'),
                review('trailer.mp4'), player(0, playing=False), player(1), player(4)])
            with patch.object(adb, 'run', return_value=subprocess.CompletedProcess(
                [], 0, f'Status: ok\nActivity: {PACKAGE}/.MainActivity\n'.encode(), b''
            )), patch.object(adb, 'screenshot', return_value=b'evidence'), patch(
                'tools.incoming_media_runtime.confirmed.time.sleep'
            ):
                result = runner.accept_video(content=False)
            self.assertEqual(result['advanceSeconds'], 3)
            self.assertEqual(runner.observe.call_count, 6)
            evidence = json.loads((Path(temporary) / 'confirmed-https-share-held-review-wait.json').read_text())
            self.assertEqual([attempt['complete'] for attempt in evidence['attempts']], [False, True])
            self.assertIn('complete active-window hierarchy', evidence['attempts'][0]['failure'])

    def test_persistently_missing_held_hierarchy_fails_before_any_open_tap(self):
        with tempfile.TemporaryDirectory() as temporary:
            adb = Adb('emulator-5554', 'confirmed-test')
            runner = ConfirmedIntake(adb, Path(temporary))
            runner.observer.production_pid = Mock(return_value='123')
            runner.observe = Mock(side_effect=[review('trailer.mp4'), RuntimeFailure('root unavailable')])
            with patch.object(adb, 'run', return_value=subprocess.CompletedProcess(
                [], 0, f'Status: ok\nActivity: {PACKAGE}/.MainActivity\n'.encode(), b''
            )) as command, patch.object(adb, 'screenshot', return_value=b'evidence'), patch(
                'tools.incoming_media_runtime.confirmed.time.sleep'
            ), patch('tools.incoming_media_runtime.confirmed.time.monotonic', side_effect=[0, 0, 0, 0, 46]):
                with self.assertRaisesRegex(RuntimeFailure, 'held-review'):
                    runner.accept_video(content=False)
            self.assertFalse(any(call.args[:3] == ('shell', 'input', 'tap') for call in command.call_args_list))

    def test_complete_held_snapshot_with_wrong_review_is_not_retried(self):
        with tempfile.TemporaryDirectory() as temporary:
            adb = Adb('emulator-5554', 'confirmed-test')
            runner = ConfirmedIntake(adb, Path(temporary))
            runner.observer.production_pid = Mock(return_value='123')
            runner.observe = Mock(side_effect=[review('trailer.mp4'), review('other.mp4'), review('trailer.mp4')])
            with patch.object(adb, 'run', return_value=subprocess.CompletedProcess(
                [], 0, f'Status: ok\nActivity: {PACKAGE}/.MainActivity\n'.encode(), b''
            )) as command, patch.object(adb, 'screenshot', return_value=b'evidence'), patch(
                'tools.incoming_media_runtime.confirmed.time.sleep'
            ):
                with self.assertRaises(RuntimeFailure):
                    runner.accept_video(content=False)
            self.assertEqual(runner.observe.call_count, 2)
            self.assertFalse(any(call.args[:3] == ('shell', 'input', 'tap') for call in command.call_args_list))

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
                command.side_effect = lambda *args, **kwargs: subprocess.CompletedProcess(
                    [], 0, b'35' if args == ('shell', 'getprop', 'ro.build.version.sdk') else data, b'')
                result = runner.prepare_video()
            self.assertEqual(write.call_args.kwargs['input'], data)
            self.assertEqual(write.call_args.args[0][-5:], ['-T', 'content', 'write', '--uri', URI])
            self.assertEqual(command.call_args.args, ('shell', '-T', 'content', 'read', '--uri', URI))
            self.assertEqual(result['providerReadbackSha256'], digest)

    def test_provider_error_with_zero_exit_is_not_mistaken_for_success(self):
        error = f'Error while accessing provider:media\njava.lang.SecurityException: {URI}\n'.encode()
        with tempfile.TemporaryDirectory() as temporary:
            adb = Adb('emulator-5554', 'confirmed-test')
            runner = ConfirmedIntake(adb, Path(temporary))
            runner.name = NAME
            runner.query = Mock(side_effect=['No result found.', ROW])
            with patch('tools.incoming_media_runtime.confirmed.download_fixture', return_value=b'fixture'), patch(
                'tools.incoming_media_runtime.confirmed.subprocess.run',
                return_value=subprocess.CompletedProcess([], 0, b'', error)
            ), patch.object(adb, 'run', return_value=subprocess.CompletedProcess([], 0, b'35', b'')) as command:
                with self.assertRaisesRegex(RuntimeFailure, 'could not write'):
                    runner.prepare_video()
            self.assertFalse(any('read' in call.args for call in command.call_args_list))
            evidence = json.loads((Path(temporary) / 'provider-write.json').read_text())
            self.assertEqual(evidence['exitCode'], 0)
            self.assertIn('SecurityException', evidence['stderr'])
            self.assertNotIn(URI, evidence['stderr'])

    def test_corrupt_readback_fails_for_both_provider_and_owned_backing_file(self):
        data = b'controlled media bytes'
        for sdk in [b'29', b'35']:
            with self.subTest(sdk=sdk), tempfile.TemporaryDirectory() as temporary:
                adb = Adb('emulator-5554', 'confirmed-test')
                runner = ConfirmedIntake(adb, Path(temporary))
                runner.name = NAME
                runner.query = Mock(side_effect=['No result found.', ROW])
                runner.query_backing_file = Mock(return_value=ROW + f', _data=/storage/emulated/0/Movies/{NAME}')
                def run(*args, **kwargs):
                    if args == ('shell', 'getprop', 'ro.build.version.sdk'):
                        return subprocess.CompletedProcess([], 0, sdk, b'')
                    if args[:3] == ('shell', 'test', '-e'):
                        return subprocess.CompletedProcess([], 1, b'', b'')
                    return subprocess.CompletedProcess([], 0, b'corrupt bytes', b'')
                with patch('tools.incoming_media_runtime.confirmed.download_fixture', return_value=data), patch(
                    'tools.incoming_media_runtime.confirmed.FIXTURE_SHA256', hashlib.sha256(data).hexdigest()
                ), patch('tools.incoming_media_runtime.confirmed.subprocess.run',
                    return_value=subprocess.CompletedProcess([], 0, b'', b'')
                ), patch.object(adb, 'run', side_effect=run):
                    with self.assertRaisesRegex(RuntimeFailure, 'bytes do not match'):
                        runner.prepare_video()
                evidence = json.loads((Path(temporary) / 'provider-read.json').read_text())
                self.assertEqual(evidence['stdoutSha256'], hashlib.sha256(b'corrupt bytes').hexdigest())

    def test_backing_file_relationship_rejects_different_path_row_and_ambiguous_rows(self):
        path = f'/storage/emulated/0/Movies/{NAME}'
        row = ROW + f', _data={path}'
        self.assertEqual(owned_backing_file(row, NAME, URI), path)
        for changed in (row.replace('/Movies/', '/Download/'), row.replace('_id=42', '_id=43'),
                        row.replace(NAME + ', mime', 'foreign.mp4, mime'), row + '\n' + row):
            with self.subTest(changed=changed), self.assertRaises(RuntimeFailure):
                owned_backing_file(changed, NAME, URI)

    def test_api29_uses_only_the_exact_owned_file_and_reports_actual_hash_method(self):
        data = b'controlled media bytes'
        digest = hashlib.sha256(data).hexdigest()
        path = f'/storage/emulated/0/Movies/{NAME}'
        with tempfile.TemporaryDirectory() as temporary:
            adb = Adb('emulator-5554', 'confirmed-test')
            runner = ConfirmedIntake(adb, Path(temporary))
            runner.name = NAME
            runner.query = Mock(side_effect=['No result found.', ROW, ROW, 'No result found.'])
            runner.query_backing_file = Mock(return_value=ROW + f', _data={path}')
            runner.observer.cleanup = Mock()
            def run(*args, **kwargs):
                if args == ('shell', 'getprop', 'ro.build.version.sdk'):
                    return subprocess.CompletedProcess([], 0, b'29', b'')
                if args[:3] == ('shell', 'test', '-e'):
                    self.assertEqual(args[3], path)
                    return subprocess.CompletedProcess([], 1, b'', b'')
                return subprocess.CompletedProcess([], 0, data if args[:2] == ('exec-out', 'cat') else b'', b'')
            with patch('tools.incoming_media_runtime.confirmed.download_fixture', return_value=data), patch(
                'tools.incoming_media_runtime.confirmed.FIXTURE_SHA256', digest
            ), patch('tools.incoming_media_runtime.confirmed.subprocess.run',
                return_value=subprocess.CompletedProcess([], 0, b'', b'')
            ) as write, patch.object(adb, 'run', side_effect=run) as command:
                report = runner.prepare_video()
                runner.cleanup()
            self.assertEqual(write.call_args.args[0][-3:], ['shell', '-T', f'cat > {path}'])
            self.assertEqual(write.call_args.kwargs['input'], data)
            self.assertEqual(report['mediaStoreBackingFileSha256'], digest)
            self.assertNotIn('providerReadbackSha256', report)
            self.assertEqual(report['readbackMethod'], 'owned-backing-file')
            self.assertEqual(runner.cleanup_result['mediaStoreBackingFile'], 'removed')
            self.assertTrue(runner.cleanup_result['completed'])
            self.assertFalse(any('write' in call.args or 'read' in call.args for call in command.call_args_list))

    def test_api29_refuses_preexisting_file_before_insert(self):
        with tempfile.TemporaryDirectory() as temporary:
            adb = Adb('emulator-5554', 'confirmed-test')
            runner = ConfirmedIntake(adb, Path(temporary))
            with patch('tools.incoming_media_runtime.confirmed.download_fixture', return_value=b'fixture'), patch.object(
                adb, 'run', side_effect=[subprocess.CompletedProcess([], 0, b'29', b''),
                                        subprocess.CompletedProcess([], 0, b'', b'')]
            ) as command:
                with self.assertRaisesRegex(RuntimeFailure, 'not confirmed absent'):
                    runner.prepare_video()
            self.assertFalse(any('insert' in call.args for call in command.call_args_list))

    def test_api29_cleanup_refuses_changed_file_or_remaining_backing_file(self):
        path = f'/storage/emulated/0/Movies/{NAME}'
        for changed in [True, False]:
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as temporary:
                adb = Adb('emulator-5554', 'confirmed-test')
                runner = ConfirmedIntake(adb, Path(temporary))
                runner.name, runner.uri, runner.backing_file = NAME, URI, path
                runner.legacy_file_io = True
                runner.query = Mock(side_effect=[ROW, 'No result found.'])
                runner.query_backing_file = Mock(return_value=ROW + ', _data=' + (
                    path.replace('/Movies/', '/Download/') if changed else path))
                runner.observer.cleanup = Mock()
                with patch.object(adb, 'run', return_value=subprocess.CompletedProcess([], 0, b'', b'')) as command:
                    with self.assertRaisesRegex(RuntimeFailure, 'cleanup'):
                        runner.cleanup()
                if changed:
                    command.assert_not_called()
                self.assertFalse(runner.cleanup_result['completed'])

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
