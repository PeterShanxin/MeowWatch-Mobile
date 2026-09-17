import json
import shutil
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


class SegmentTimelineTests(unittest.TestCase):
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
