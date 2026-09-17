from pathlib import Path
import unittest

from tools.android_install.runner import ACTIVITY, PACKAGE, RuntimeFailure
from tools.incoming_media_runtime.run import CASES, Case, Runner, center, exact, launch_arguments, require_case_review, require_review


def node(label: str, clickable: bool = False, package: str = PACKAGE) -> str:
    return (f'<node text="{label}" content-desc="" package="{package}" '
            f'clickable="{str(clickable).lower()}" enabled="true" '
            'visible-to-user="true" bounds="[10,20][110,60]" />')


def review(filename: str) -> str:
    return '<hierarchy>' + ''.join([
        node('Open shared video?'), node(filename), node('Cancel', True), node('Open video', True),
    ]) + '</hierarchy>'


class IncomingRuntimeTests(unittest.TestCase):
    def test_cold_send_uses_exported_normal_activity_and_non_resolving_fixture(self):
        command = launch_arguments(CASES[0])
        self.assertEqual(command[:6], ['shell', 'am', 'start', '-W', '-n', ACTIVITY])
        self.assertIn('android.intent.action.SEND', command)
        self.assertIn('android.intent.extra.TEXT', command)
        self.assertEqual(command[-1], 'https://example.invalid/meowwatch-cold-send.mp4')

    def test_view_uses_uri_data_without_integration_test_or_debug_arguments(self):
        command = launch_arguments(CASES[3])
        self.assertIn('android.intent.action.VIEW', command)
        self.assertIn('-d', command)
        self.assertNotIn('--es', command)
        self.assertNotIn('integration_test', ' '.join(command))

    def test_unapproved_input_cannot_become_an_adb_shell_fixture(self):
        with self.assertRaises(ValueError):
            launch_arguments(Case('unsafe;rm', 'SEND', True))

    def test_native_invite_preserves_complete_query_as_one_shell_argument(self):
        import shlex
        case = CASES[4]
        command = launch_arguments(case)
        decoded = shlex.split(' '.join(command))
        self.assertIn('android.intent.action.VIEW', decoded)
        self.assertEqual(decoded[-1],
                         f'meowwatch://join?room={case.room}&server=syncplay.pl&port=8995')

    def test_invitation_requires_actual_room_server_and_explicit_join(self):
        case = CASES[4]
        xml = '<hierarchy>' + ''.join([
            node('Room invitation received'), node(f'Room: {case.room}'),
            node('Server: syncplay.pl:8995'), node('Join this room', True),
        ]) + '</hierarchy>'
        require_case_review(xml, case)
        for missing in [case.room, 'syncplay.pl:8995', 'Join this room']:
            with self.assertRaises(RuntimeFailure):
                require_case_review(xml.replace(missing, 'missing'), case)
        with self.assertRaises(RuntimeFailure):
            require_case_review(xml.replace('</hierarchy>', node('Open shared video?') + '</hierarchy>'), case)

    def test_exact_review_requires_source_and_both_confirmation_choices(self):
        xml = review(CASES[0].filename)
        require_review(xml, CASES[0].filename)
        for missing in ['Open shared video?', CASES[0].filename, 'Cancel', 'Open video']:
            with self.assertRaises(RuntimeFailure):
                require_review(xml.replace(missing, 'missing'), CASES[0].filename)

    def test_duplicate_dialog_or_wrong_package_is_not_accepted(self):
        xml = review(CASES[0].filename)
        with self.assertRaises(RuntimeFailure):
            require_review(xml.replace('</hierarchy>', node('Open shared video?') + '</hierarchy>'), CASES[0].filename)
        with self.assertRaises(RuntimeFailure):
            require_review(xml.replace(PACKAGE, 'other.app'), CASES[0].filename)

    def test_button_geometry_requires_positive_visible_bounds(self):
        button = exact(review(CASES[0].filename), 'Cancel', clickable=True)[0]
        self.assertEqual(center(button), (60, 40))
        button.set('bounds', '[10,20][10,20]')
        with self.assertRaises(RuntimeFailure):
            center(button)

    def test_runner_rejects_unscoped_physical_device_serial(self):
        with self.assertRaises(ValueError):
            Runner('physical-device', Path('unused'))


if __name__ == '__main__':
    unittest.main()
