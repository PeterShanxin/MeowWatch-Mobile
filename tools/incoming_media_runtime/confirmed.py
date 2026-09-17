"""Confirm two real incoming videos through the unchanged production player."""

from __future__ import annotations

from dataclasses import asdict, dataclass
import hashlib
import json
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import time
import urllib.request
import xml.etree.ElementTree as ET

from tools.android_install.runner import ACTIVITY, Adb, PACKAGE, RuntimeFailure, focused_component, launch_output_succeeded
from tools.android_native_ui.observer import DEFAULT_APK, NativeUiObserver, ObserverIntegrityFailure
from tools.incoming_media_runtime.run import center, exact, nodes, require_review


FIXTURE_URL = "https://media.w3.org/2010/05/sintel/trailer.mp4"
FIXTURE_SHA256 = "b670602fa00934ca27c4351bb0efe7ea7a07fae57284e44226025eeed7c51254"
MAX_FIXTURE_BYTES = 8 * 1024 * 1024
MEDIA_COLLECTION = "content://media/external/video/media"
_MEDIA_URI = re.compile(re.escape(MEDIA_COLLECTION) + r"/[1-9][0-9]*")


def download_fixture() -> bytes:
    with urllib.request.urlopen(FIXTURE_URL, timeout=30) as response:
        if response.geturl() != FIXTURE_URL:
            raise RuntimeFailure("the fixed HTTPS fixture unexpectedly redirected")
        data = response.read(MAX_FIXTURE_BYTES + 1)
    if len(data) > MAX_FIXTURE_BYTES or hashlib.sha256(data).hexdigest() != FIXTURE_SHA256:
        raise RuntimeFailure("the public playback fixture differs from its pinned bytes")
    return data


def owned_row(output: str, name: str) -> str:
    if re.fullmatch(r"meowwatch-intake-[a-f0-9]{32}\.mp4", name) is None:
        raise ValueError("invalid owned MediaStore display name")
    match = re.fullmatch(
        rf"Row: 0 _id=([1-9][0-9]*), _display_name={re.escape(name)}, mime_type=video/mp4\s*",
        output,
    )
    if match is None:
        raise RuntimeFailure("the exact owned MediaStore row is missing or ambiguous")
    return f"{MEDIA_COLLECTION}/{match[1]}"


def temporary_read_grant(output: str, uri: str) -> dict[str, object]:
    if _MEDIA_URI.fullmatch(uri) is None:
        raise ValueError("invalid fixture content URI")
    blocks = re.split(r"(?=UriPermission\{)", output)
    matches = [block for block in blocks if re.search(re.escape(uri) + r"(?=[\s}])", block)
               and re.search(r"\btargetPkg=" + re.escape(PACKAGE) + r"(?=\s|$)", block)]
    if len(matches) != 1:
        raise RuntimeFailure("the exact fixture URI has no unique MeowWatch grant")
    flags = re.findall(r"\b(mode|owned|global|persistable|persisted)=0x([a-fA-F0-9]+)\b", matches[0])
    if len(flags) != 5 or len(dict(flags)) != 5:
        raise RuntimeFailure("the fixture URI grant flags are incomplete or ambiguous")
    values = {key: int(value, 16) for key, value in flags}
    if values['mode'] != 1 or values['owned'] != 1 or any(values[key] for key in ('global', 'persistable', 'persisted')):
        raise RuntimeFailure("the fixture URI grant is not temporary read-only access")
    return {"exactUriSha256": hashlib.sha256(uri.encode()).hexdigest(), "targetPackage": PACKAGE,
            "readGranted": True, "writeGranted": False, "persisted": False, "flags": values}


@dataclass(frozen=True)
class Playback:
    position_seconds: int
    duration_seconds: int
    playing: bool


def playback(xml: str, title: str) -> Playback:
    if len(exact(xml, title)) != 1:
        raise RuntimeFailure("the native player does not show the expected incoming video")
    current_nodes = nodes(xml)
    if len([node for node in current_nodes if node.get('class', '').endswith('SeekBar')]) != 1:
        raise RuntimeFailure("the actual player timeline is missing or ambiguous")
    times = set()
    for node in current_nodes:
        for label in (node.get('text', ''), node.get('content-desc', '')):
            if re.fullmatch(r"\d+:[0-5]\d", label):
                minutes, seconds = map(int, label.split(':'))
                times.add(minutes * 60 + seconds)
    ordered = sorted(times)
    if len(ordered) != 2 or ordered[1] != 52 or ordered[0] >= 52:
        raise RuntimeFailure("the incoming fixture elapsed time and actual duration are unavailable")
    play = [node for label in ('Play', 'Play together') for node in exact(xml, label, clickable=True)]
    pause = [node for label in ('Pause', 'Pause together') for node in exact(xml, label, clickable=True)]
    if len(play) + len(pause) != 1:
        raise RuntimeFailure("the production player must have one enabled playback action")
    return Playback(ordered[0], ordered[1], bool(pause))


def require_advance(before: Playback, after: Playback) -> int:
    delta = after.position_seconds - before.position_seconds
    if not before.playing or not after.playing or delta < 2 or before.duration_seconds != after.duration_seconds:
        raise RuntimeFailure("the actual incoming video did not advance by two displayed seconds")
    return delta


class ConfirmedIntake:
    def __init__(self, adb: Adb, output: Path, observer_apk: Path = DEFAULT_APK) -> None:
        self.adb, self.output = adb, output
        self.observer = NativeUiObserver(adb, observer_apk)
        self.name = f"meowwatch-intake-{secrets.token_hex(16)}.mp4"
        self.uri: str | None = None
        self.cleanup_result: dict[str, object] = {"mediaStoreRow": "not-created"}

    def query(self) -> str:
        where = shlex.quote(f"_display_name='{self.name}'")
        return self.adb.run('shell', 'content', 'query', '--uri', MEDIA_COLLECTION,
                            '--projection', '_id:_display_name:mime_type', '--where', where).stdout.decode().strip()

    def prepare_video(self) -> dict[str, object]:
        data = download_fixture()
        if self.query() != 'No result found.':
            raise RuntimeFailure("the unique fixture MediaStore name already exists")
        self.cleanup_result['mediaStoreRow'] = 'retained-ownership-unconfirmed'
        self.adb.run('shell', 'content', 'insert', '--uri', MEDIA_COLLECTION,
                     '--bind', f'_display_name:s:{self.name}', '--bind', 'mime_type:s:video/mp4',
                     '--bind', 'relative_path:s:Movies/')
        self.uri = owned_row(self.query(), self.name)
        self.cleanup_result['mediaStoreRow'] = 'owned'
        result = subprocess.run(self.adb.prefix + ['shell', '-T', 'content', 'write', '--uri', self.uri],
                                input=data, capture_output=True, timeout=40, check=False)
        if result.returncode:
            raise RuntimeFailure("could not write the fixture through its Android content provider")
        readback = self.adb.run('exec-out', 'content', 'read', '--uri', self.uri, timeout=40).stdout
        if hashlib.sha256(readback).hexdigest() != FIXTURE_SHA256:
            raise RuntimeFailure("the provider's video bytes do not match the public fixture")
        return {'publicSource': FIXTURE_URL, 'sha256': FIXTURE_SHA256, 'bytes': len(data),
                'providerReadbackSha256': FIXTURE_SHA256,
                'contentUriSha256': hashlib.sha256(self.uri.encode()).hexdigest()}

    def observe(self) -> str:
        xml, window = self.observer.observe()
        focused_component(window)
        return xml

    def wait(self, phase: str, check, seconds: float = 45):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            try:
                xml = self.observe()
                value = check(xml)
                self.output.joinpath(f'{phase}.xml').write_text(xml, encoding='utf-8')
                return xml, value
            except ObserverIntegrityFailure:
                raise
            except (RuntimeFailure, subprocess.TimeoutExpired):
                time.sleep(0.3)
        raise RuntimeFailure(f'{phase}: fresh native acceptance observation timed out')

    def tap(self, node: ET.Element) -> None:
        x, y = center(node)
        self.adb.run('shell', 'input', 'tap', str(x), str(y))

    def accept_video(self, *, content: bool) -> dict[str, object]:
        phase = 'confirmed-content-view' if content else 'confirmed-https-share'
        title = 'Shared video' if content else 'trailer.mp4'
        pid = self.observer.production_pid()
        arguments = ['shell', 'am', 'start', '-W', '-n', ACTIVITY]
        if content:
            if self.uri is None:
                raise RuntimeFailure('provider fixture is missing')
            arguments += ['-a', 'android.intent.action.VIEW', '-t', 'video/mp4',
                          '--grant-read-uri-permission', '-d', self.uri]
        else:
            arguments += ['-a', 'android.intent.action.SEND', '-t', 'text/plain',
                          '--es', 'android.intent.extra.TEXT', FIXTURE_URL]
        launch = self.adb.run(*arguments, timeout=35).stdout.decode()
        if not launch_output_succeeded(launch):
            raise RuntimeFailure('Android did not deliver the confirmed-video intent')
        xml, _ = self.wait(phase + '-review', lambda value: require_review(value, title))
        self.output.joinpath(phase + '-review.png').write_bytes(self.adb.screenshot())
        time.sleep(1)
        xml = self.observe()
        require_review(xml, title)
        grant = None
        if content:
            permissions = self.adb.run('shell', 'dumpsys', 'activity', 'permissions').stdout.decode()
            grant = temporary_read_grant(permissions, self.uri)
            if len(exact(xml, 'This app granted temporary video access. To keep it in Continue Watching, choose it again using Open a video.')) != 1:
                raise RuntimeFailure('production did not identify the temporary content grant')
        self.tap(exact(xml, 'Open video', clickable=True)[0])

        def loaded(value):
            state = playback(value, title)
            if state.playing or state.position_seconds > 1:
                raise RuntimeFailure('incoming confirmation did not load a paused video')
            return state
        xml, _ = self.wait(phase + '-loaded-paused', loaded)
        self.tap([node for label in ('Play', 'Play together') for node in exact(xml, label, clickable=True)][0])

        def playing(value):
            state = playback(value, title)
            if not state.playing:
                raise RuntimeFailure('the native incoming video is not playing')
            return state
        _, before = self.wait(phase + '-playing', playing)
        self.output.joinpath(phase + '-playing.png').write_bytes(self.adb.screenshot())

        def advanced(value):
            state = playing(value)
            require_advance(before, state)
            return state
        xml, after = self.wait(phase + '-advanced', advanced, seconds=20)
        self.output.joinpath(phase + '-advanced.png').write_bytes(self.adb.screenshot())
        if self.observer.production_pid() != pid:
            raise ObserverIntegrityFailure('incoming playback changed the normal application process')
        self.tap([node for label in ('Pause', 'Pause together') for node in exact(xml, label, clickable=True)][0])
        return {'case': phase, 'reviewRemainedUntilChoice': True, 'openActionInvoked': True,
                'explicitPlayInvoked': True, 'sameProcess': True, 'temporaryReadGrant': grant,
                'before': asdict(before), 'after': asdict(after), 'advanceSeconds': require_advance(before, after)}

    def cleanup(self) -> None:
        self.cleanup_result['completed'] = False
        try:
            try:
                if self.uri is not None:
                    try:
                        if owned_row(self.query(), self.name) != self.uri:
                            raise RuntimeFailure('fixture owner changed')
                        self.adb.run('shell', 'content', 'delete', '--uri', self.uri)
                        if self.query() != 'No result found.':
                            raise RuntimeFailure('fixture deletion was not confirmed')
                        self.cleanup_result['mediaStoreRow'] = 'removed'
                    except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
                        self.cleanup_result['mediaStoreRow'] = 'retained-owner-or-cleanup-unconfirmed'
                        self.cleanup_result['mediaStoreFailure'] = (
                            str(error) if isinstance(error, RuntimeFailure) else type(error).__name__)
                        raise RuntimeFailure('MediaStore fixture cleanup unconfirmed; row retained or removal unknown') from None
                elif self.cleanup_result['mediaStoreRow'] != 'not-created':
                    raise RuntimeFailure('MediaStore fixture cleanup unconfirmed; insertion ownership unknown, row retained')
            finally:
                self.observer.cleanup()
            self.cleanup_result['completed'] = True
        finally:
            self.output.joinpath('confirmed-cleanup.json').write_text(
                json.dumps(self.cleanup_result, indent=2), encoding='utf-8')
            self.output.joinpath('confirmed-observations.json').write_text(
                json.dumps(self.observer.observations, indent=2), encoding='utf-8')

    def run(self) -> dict[str, object]:
        report: dict[str, object] = {'completed': False, 'cases': []}
        playback_completed = False
        try:
            report['observer'] = self.observer.install()
            report['fixture'] = self.prepare_video()
            cases = []
            report['cases'] = cases
            for content in (False, True):
                cases.append(self.accept_video(content=content))
            playback_completed = True
        except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
            report['failure'] = str(error) if isinstance(error, RuntimeFailure) else type(error).__name__
            raise
        finally:
            cleanup_completed = False
            try:
                self.cleanup()
                cleanup_completed = True
            except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
                report['cleanupFailure'] = str(error) if isinstance(error, RuntimeFailure) else type(error).__name__
                raise
            finally:
                report['cleanup'] = dict(self.cleanup_result)
                report['completed'] = playback_completed and cleanup_completed
                self.output.joinpath('confirmed-result.json').write_text(
                    json.dumps(report, indent=2), encoding='utf-8')
        return report
