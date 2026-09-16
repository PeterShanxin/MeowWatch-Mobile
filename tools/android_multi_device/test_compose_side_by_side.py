import tempfile
import unittest
from decimal import Decimal
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compose_side_by_side as composer


class AlignmentTests(unittest.TestCase):
    def test_later_tablet_keeps_measured_offset(self) -> None:
        alignment = composer.compute_alignment(
            {
                "phone_first_segment_ns": "1789536738781789772",
                "tablet_first_segment_ns": "1789536738783921543",
            }
        )

        self.assertEqual(alignment.phone_delay_seconds, Decimal("0"))
        self.assertEqual(alignment.tablet_delay_seconds, Decimal("0.002131771"))

    def test_later_phone_gets_offset(self) -> None:
        alignment = composer.compute_alignment(
            {
                "phone_first_segment_ns": "2000000000",
                "tablet_first_segment_ns": "1250000000",
            }
        )

        self.assertEqual(alignment.phone_delay_seconds, Decimal("0.75"))
        self.assertEqual(alignment.tablet_delay_seconds, Decimal("0"))

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
            duration=Decimal("10"),
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
