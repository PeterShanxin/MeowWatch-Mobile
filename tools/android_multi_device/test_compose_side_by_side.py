import json
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compose_side_by_side as composer


def segment(index: int, start: str, duration: str | None) -> composer.Segment:
    probe = (
        {"streams": [{"duration": duration, "width": 32, "height": 64}]}
        if duration
        else None
    )
    return composer.Segment(
        index,
        int(Decimal(start) * 1_000_000_000),
        Path(f"phone-{index:03d}.mp4"),
        probe,
    )


def clear_fixture_duration(path: Path) -> None:
    """Build a native-like untimed fixture; alter timing, never compressed frames."""
    data = bytearray(path.read_bytes())
    def visit(start, end):
        while start < end:
            size, kind = struct.unpack_from(">I4s", data, start)
            assert size >= 8 and start + size <= end
            payload = start + 8
            if kind == b"edts":
                data[start + 4:start + 8] = b"free"
            elif kind in (b"moov", b"trak", b"mdia", b"minf", b"stbl"):
                visit(payload, start + size)
            elif kind in (b"mvhd", b"mdhd", b"tkhd"):
                assert data[payload] == 0
                struct.pack_into(">I", data, payload + (20 if kind == b"tkhd" else 16), 0)
            elif kind in (b"stts", b"elst"):
                assert data[payload] == 0
                count = struct.unpack_from(">I", data, payload + 4)[0]
                for index in range(count):
                    offset = payload + 8 + index * (8 if kind == b"stts" else 12)
                    struct.pack_into(">I", data, offset + (4 if kind == b"stts" else 0), 0)
            start += size
    visit(0, len(data))
    path.write_bytes(data)


class SegmentTimelineTests(unittest.TestCase):
    def test_retained_untimed_frame_has_no_interval_or_rendered_source(self) -> None:
        still = composer.Segment(1, 2_000_000_000, Path("still.mp4"),
                                 {"streams": [{"duration": "0", "width": 32, "height": 64}]},
                                 {"decodedFrameCount": 1})
        segments = [segment(0, "0", "1"), still]
        self.assertEqual(still.status, "retained-but-no-duration")
        self.assertEqual(composer.recording_gaps(composer.segment_intervals(segments, 0), Decimal(3)),
                         [(Decimal(1), Decimal(3))])
        graph, sources = composer.build_timeline_graph("phone", segments, 0, Decimal(3),
                                                       Path("/tmp/font.ttf"), 0, 350, 776)
        self.assertNotIn(still.path, sources)
        self.assertNotIn("phone_segment_1", ";".join(graph))
        self.assertEqual(composer.bounded_timeline_duration((segments, [segment(0, "0", "3")]), 0), Decimal(3))
        with self.assertRaisesRegex(ValueError, "No positive-duration"):
            composer.bounded_timeline_duration(([still],), 0)
        with self.assertRaisesRegex(ValueError, "no known end"):
            composer.bounded_timeline_duration((segments,), 0)
        with self.assertRaisesRegex(ValueError, "must be positive"):
            composer.video_duration(still.probe)

    def test_rotation_gap_and_shorter_device_tail_are_retained(self) -> None:
        intervals = composer.segment_intervals(
            [
                segment(0, "0.25", "1.5"),
                segment(1, "3", "2"),
            ],
            0,
        )
        self.assertEqual(
            intervals, [(Decimal("0.25"), Decimal("1.75")), (Decimal(3), Decimal(5))]
        )
        self.assertEqual(
            composer.recording_gaps(intervals, Decimal(7)),
            [
                (Decimal(0), Decimal("0.25")),
                (Decimal("1.75"), Decimal(3)),
                (Decimal(5), Decimal(7)),
            ],
        )

    def test_missing_middle_segment_stays_a_gap(self) -> None:
        intervals = composer.segment_intervals(
            [
                segment(0, "0", "1"),
                segment(1, "2", None),
                segment(2, "4", "1"),
            ],
            0,
        )
        self.assertEqual(
            composer.recording_gaps(intervals, Decimal(5)), [(Decimal(1), Decimal(4))]
        )

    def test_later_command_takes_over_estimated_overlap(self) -> None:
        intervals = composer.segment_intervals(
            [segment(0, "0", "3"), segment(1, "2", "3")], 0
        )
        self.assertEqual(
            intervals, [(Decimal(0), Decimal(2)), (Decimal(2), Decimal(5))]
        )
        self.assertEqual(composer.recording_gaps(intervals, Decimal(5)), [])

    def test_missing_timing_row_fails_instead_of_collapsing_segment(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "recorder-control").mkdir()
            (root / "recorder-control/phone-segments.tsv").write_text(
                "0\t1\tphone-000.mp4\n2\t3\tphone-002.mp4\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "missing phone segment"):
                composer.read_segments(
                    "phone",
                    root / "phone/native.mp4",
                    root / "recording-session.tsv",
                    "ffprobe",
                )

    def test_missing_native_file_is_explicit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "recorder-control").mkdir()
            (root / "recorder-control/phone-segments.tsv").write_text(
                "0\t1\tphone-000.mp4\n", encoding="utf-8"
            )
            result = composer.read_segments(
                "phone",
                root / "phone/native.mp4",
                root / "recording-session.tsv",
                "ffprobe",
            )
            self.assertIsNone(result[0].probe)

    def test_graph_has_per_segment_offsets_and_no_frozen_last_frame(self) -> None:
        graph, sources = composer.build_timeline_graph(
            "phone",
            [segment(0, "0", "1"), segment(1, "3", "1")],
            0,
            Decimal(6),
            Path("/tmp/font.ttf"),
            0,
            350,
            776,
        )
        text = ";".join(graph)
        self.assertIn("RECORDING GAP", text)
        self.assertIn("setpts=PTS+3.000000/TB", text)
        self.assertIn("eof_action=pass:repeatlast=0", text)
        self.assertIn("lt(t,4.000000)", text)
        self.assertEqual(len(sources), 2)


@unittest.skipUnless(
    shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg required"
)
class RenderedTimelineTests(unittest.TestCase):
    def test_real_single_frame_retention_rejects_multiple_frames_and_corruption(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / "phone/segments"
            folder.mkdir(parents=True)
            control = root / "recorder-control"
            control.mkdir()
            (control / "phone-segments.tsv").write_text("0\t1000000000\tphone-000.mp4\n")
            for count in (1, 2):
                path = folder / "phone-000.mp4"
                subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                                "color=red:s=64x128:r=10", "-frames:v", str(count),
                                "-c:v", "libx264", "-threads", "1", str(path)], check=True)
                clear_fixture_duration(path)
                probe = composer.probe_video("ffprobe", path)
                self.assertTrue(composer.has_explicit_zero_duration(probe))
                original_hash = composer.sha256(path)
                if count == 2:
                    with self.assertRaisesRegex(ValueError, "exactly one"):
                        composer.read_segments("phone", root / "phone/native.mp4",
                                               root / "recording-session.tsv", "ffprobe")
                    continue
                result = composer.read_segments("phone", root / "phone/native.mp4",
                                                root / "recording-session.tsv", "ffprobe")
                self.assertEqual(result[0].duration, 0)
                self.assertEqual(result[0].start_ns, 1_000_000_000)
                self.assertEqual(result[0].no_duration_validation["decodedFrameCount"], 1)
                self.assertEqual(composer.sha256(path), original_hash)
                self.assertEqual(result[0].probe, probe)
                corrupt = root / "corrupt.mp4"
                corrupt.write_bytes(b"not a video")
                with self.assertRaises(subprocess.CalledProcessError):
                    composer.validate_untimed_single_frame("ffmpeg", corrupt, probe)

    def test_rendered_gap_and_shorter_tail_are_black_not_repeated_video(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "red.mp4"
            subprocess.run(
                [
                    "ffmpeg",
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-f",
                    "lavfi",
                    "-i",
                    "color=red:s=64x128:r=10:d=1",
                    "-c:v",
                    "libx264",
                    "-threads",
                    "1",
                    str(source),
                ],
                check=True,
            )
            probe = composer.probe_video("ffprobe", source)
            segments = [
                composer.Segment(0, 0, source, probe),
                composer.Segment(1, 2_000_000_000, source, probe),
            ]
            graph, sources = composer.build_timeline_graph(
                "phone", segments, 0, Decimal(4), composer.find_font(), 0, 350, 776
            )
            output = root / "timeline.mp4"
            subprocess.run(
                [
                    "ffmpeg",
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-filter_complex_threads",
                    "1",
                    *[item for path in sources for item in ("-i", str(path))],
                    "-filter_complex",
                    ";".join(graph),
                    "-map",
                    "[phone_timeline]",
                    "-an",
                    "-t",
                    "4",
                    "-c:v",
                    "libx264",
                    "-threads",
                    "1",
                    "-preset",
                    "ultrafast",
                    str(output),
                ],
                check=True,
            )
            for when, is_gap in (
                ("0.5", False),
                ("1.5", True),
                ("2.5", False),
                ("3.5", True),
            ):
                pixel = subprocess.check_output(
                    [
                        "ffmpeg",
                        "-hide_banner",
                        "-loglevel",
                        "error",
                        "-ss",
                        when,
                        "-i",
                        str(output),
                        "-frames:v",
                        "1",
                        "-vf",
                        "crop=2:2:100:100",
                        "-f",
                        "rawvideo",
                        "-pix_fmt",
                        "rgb24",
                        "pipe:1",
                    ]
                )
                self.assertEqual(len(pixel), 12)
                self.assertEqual(pixel[0] < 20, is_gap, f"gap pixel at {when}s")
            self.assertGreaterEqual(
                composer.video_duration(composer.probe_video("ffprobe", output)),
                Decimal(4),
            )

            control = root / "recorder-control"
            control.mkdir()
            timing = root / "recording-session.tsv"
            timing.write_text(
                "phone_first_segment_ns\t0\ntablet_first_segment_ns\t0\n",
                encoding="utf-8",
            )
            for role, second_start in (("phone", 2), ("tablet", 4)):
                folder = root / role / "segments"
                folder.mkdir(parents=True)
                for index in (0, 1):
                    shutil.copyfile(source, folder / f"{role}-{index:03d}.mp4")
                (control / f"{role}-segments.tsv").write_text(
                    f"0\t0\t{role}-000.mp4\n1\t{second_start * 1_000_000_000}\t{role}-001.mp4\n",
                    encoding="utf-8",
                )
            raw_hash = composer.sha256(root / "phone/segments/phone-000.mp4")
            composed = root / "full-timeline.mp4"
            arguments = [
                str(root / "phone/native.mp4"),
                str(root / "tablet/native.mp4"),
                str(timing),
                str(composed),
                "--preset",
                "ultrafast",
            ]
            self.assertEqual(composer.main(arguments), 0)
            manifest = json.loads(
                composed.with_suffix(".mp4.manifest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(manifest["alignment"]["commonDurationSeconds"], "5.000000")
            self.assertEqual(
                manifest["sources"]["phone"]["recordingGaps"][-1],
                {"startSeconds": "3.000000", "endSeconds": "5.000000"},
            )
            self.assertEqual(
                composer.sha256(root / "phone/segments/phone-000.mp4"), raw_hash
            )
            (root / "tablet/segments/tablet-001.mp4").unlink()
            with self.assertRaisesRegex(ValueError, "Missing trailing segment"):
                composer.main(arguments)


class AlignmentTests(unittest.TestCase):
    def test_later_tablet_keeps_measured_offset(self) -> None:
        alignment = composer.compute_alignment(
            {
                "phone_first_segment_ns": "1789536738781789772",
                "tablet_first_segment_ns": "1789536738783921543",
            }
        )

        self.assertEqual(alignment.phone_delay_seconds, Decimal(0))
        self.assertEqual(alignment.tablet_delay_seconds, Decimal("0.002131771"))

    def test_later_phone_gets_offset(self) -> None:
        alignment = composer.compute_alignment(
            {
                "phone_first_segment_ns": "2000000000",
                "tablet_first_segment_ns": "1250000000",
            }
        )

        self.assertEqual(alignment.phone_delay_seconds, Decimal("0.75"))
        self.assertEqual(alignment.tablet_delay_seconds, Decimal(0))

    def test_invalid_timing_fails_closed(self) -> None:
        with self.assertRaisesRegex(ValueError, "integer phone/tablet"):
            composer.compute_alignment({"phone_first_segment_ns": "5"})

    def test_tsv_rejects_non_pair_rows(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            timing = Path(directory) / "recording-session.tsv"
            timing.write_text("phone_serial\temulator-5554\textra\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Malformed timing row"):
                composer.read_tsv(timing)


class FilterGraphTests(unittest.TestCase):
    def test_graph_includes_alignment_sources_and_honest_status(self) -> None:
        alignment = composer.compute_alignment(
            {
                "phone_first_segment_ns": "1000000000",
                "tablet_first_segment_ns": "1002131771",
            }
        )

        graph = composer.build_filter_graph(
            alignment=alignment,
            duration=Decimal("12.5"),
            font_file=Path("/tmp/font.ttf"),
            phone_label="PHONE / emulator-5554 / native recording",
            tablet_label="TABLET / emulator-5556 / native recording",
            result_label="RUN RESULT: FAILED - PAUSE CONVERGENCE",
        )

        self.assertIn("start_duration=0.000000", graph)
        self.assertIn("start_duration=0.002132", graph)
        self.assertIn("PHONE / emulator-5554 / native recording", graph)
        self.assertIn("TABLET / emulator-5556 / native recording", graph)
        self.assertIn(composer.DEVELOPMENT_LABEL, graph)
        self.assertIn("RUN RESULT\\: FAILED - PAUSE CONVERGENCE", graph)

    def test_landscape_tablet_gets_a_wide_device_frame(self) -> None:
        alignment = composer.compute_alignment(
            {
                "phone_first_segment_ns": "1",
                "tablet_first_segment_ns": "1",
            }
        )

        graph = composer.build_filter_graph(
            alignment=alignment,
            duration=Decimal(10),
            font_file=Path("/tmp/font.ttf"),
            phone_label="phone",
            tablet_label="tablet",
            result_label=None,
            tablet_is_landscape=True,
        )

        self.assertIn("scale=920:600", graph)
        self.assertIn("pad=960:648", graph)
        self.assertIn("overlay=x=710:y=238", graph)


if __name__ == "__main__":
    unittest.main(verbosity=2)
