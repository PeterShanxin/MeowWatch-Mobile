import copy
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.submission_demo import compose


def fixture(root: Path, real: bool = False) -> Path:
    """Disposable, visibly synthetic color fixtures; never native evidence."""
    sources = {}
    for role, size in (("phone", (90, 180)), ("tablet", (320, 180))):
        path = root / f"synthetic-{role}.mp4"
        if real:
            graph = ";".join(
                f"color={color}:s={size[0]}x{size[1]}:r=30:d=1[v{index}]"
                for index, color in enumerate(("red", "lime", "blue")))
            graph += ";[v0][v1][v2]concat=n=3:v=1:a=0[out]"
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
                            "-filter_complex_threads", "1", "-filter_complex", graph,
                            "-map", "[out]", "-c:v", "libx264", "-threads", "1",
                            "-pix_fmt", "yuv420p", str(path)], check=True)
        else:
            path.write_bytes(f"Synthetic {role}".encode())
        sources[role] = {"path": path.name, "sha256": compose.sha256(path),
                         "width": size[0], "height": size[1], "kind": "synthetic-fixture",
                         "runtime": "Synthetic color fixture", "run": "disposable-smoke",
                         "commit": "synthetic-test-only"}
    manifest = {"schemaVersion": 2, "sources": {}}
    for role, start in (("phone", 0), ("tablet", 0.5)):
        manifest["sources"][role] = {
            "segments": [{"path": sources[role]["path"], "sha256": sources[role]["sha256"],
                          "status": "available", "estimatedStartSeconds": str(start),
                          "estimatedEndSeconds": str(start + 3)}],
            "recordingGaps": [{"startSeconds": "0", "endSeconds": str(start)}] if start else [],
        }
    timeline = root / "synthetic-timing.json"
    timeline.write_text(json.dumps(manifest), encoding="utf-8")
    edl = {
        "schema_version": 1, "purpose": "synthetic-smoke", "sources": sources,
        "timelines": {"together": {"path": timeline.name, "sha256": compose.sha256(timeline)}},
        "shots": [
            {"id": "title", "kind": "card", "duration": 0.5, "title": "Movie night, together.",
             "caption": "Disposable synthetic render test. This is not app footage."},
            {"id": "paired", "kind": "pair", "timeline": "together", "phone": "phone", "tablet": "tablet",
             "in": 1, "out": 2, "speed": 1, "phone_label": "Phone / synthetic", "tablet_label": "Tablet / synthetic",
             "title": "Together, at your own pace", "caption": "Color transitions verify the recorded offsets. These are synthetic test sources.",
             "disclosure": "TEST FIXTURE ONLY / NOT A PRODUCT DEMONSTRATION"},
            {"id": "single", "kind": "single", "source": "phone", "device": "phone", "in": 2, "out": 3,
             "speed": 1, "label": "Phone / synthetic", "title": "A place for movie night",
             "caption": "Synthetic clip. Production footage will replace this test input.",
             "disclosure": "TEST FIXTURE ONLY / NOT A PRODUCT DEMONSTRATION"},
            {"id": "end", "kind": "card", "duration": 0.5, "title": "Watch together, wherever.",
             "caption": "github.com/PeterShanxin/MeowWatch-Mobile"},
        ],
    }
    path = root / "synthetic.edl.json"
    path.write_text(json.dumps(edl, indent=2), encoding="utf-8")
    return path


class EdlValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.edl_path = fixture(self.root)
        self.edl = compose.read_json(self.edl_path)
        self.probe = patch.object(compose, "probe", side_effect=self.fake_probe)
        self.probe.start()
        self.addCleanup(self.probe.stop)

    @staticmethod
    def fake_probe(path, _ffprobe):
        size = (90, 180) if "phone" in str(path) else (320, 180)
        return {"width": size[0], "height": size[1], "duration": 3,
                "frame_rate": "30/1", "codec": "h264", "raw": {}}

    def validate(self):
        self.edl_path.write_text(json.dumps(self.edl), encoding="utf-8")
        return compose.validate(self.edl_path)

    def test_common_window_uses_measured_offsets_and_full_source_frames(self):
        plan = self.validate()
        self.assertEqual(plan["duration"], 3)
        pair = plan["shots"][1]
        self.assertEqual([(c["in"], c["out"]) for c in pair["clips"]], [(1, 2), (0.5, 1.5)])
        self.assertEqual(compose.fit(plan["sources"]["phone"], (0, 0, 360, 780)), (0, 30, 360, 720))

    def test_changed_source_hash_fails_before_render(self):
        (self.root / "synthetic-phone.mp4").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
            self.validate()

    def test_declared_dimensions_must_match_the_video(self):
        self.edl["sources"]["phone"]["width"] = 1080
        with self.assertRaisesRegex(ValueError, "Dimensions disagree"):
            self.validate()

    def test_synthetic_fixture_cannot_be_exported_as_submission_edit(self):
        self.edl["purpose"] = "submission-edit"
        with self.assertRaisesRegex(ValueError, "Synthetic and native"):
            self.validate()

    def test_paired_gap_or_boundary_cannot_be_concealed(self):
        self.edl["shots"][1].update({"in": 0, "out": 1})
        with self.assertRaisesRegex(ValueError, "recording gap"):
            self.validate()

    def test_independent_retiming_and_speed_are_rejected(self):
        original = copy.deepcopy(self.edl)
        self.edl["shots"][1]["phone_in"] = 0
        with self.assertRaisesRegex(ValueError, "Unsupported shot fields"):
            self.validate()
        self.edl = original
        self.edl["shots"][1]["speed"] = 2
        with self.assertRaisesRegex(ValueError, "Only 1x"):
            self.validate()

    def test_single_clip_cannot_extend_or_freeze_beyond_source(self):
        self.edl["shots"][2]["out"] = 3.1
        with self.assertRaisesRegex(ValueError, "exceeds real footage"):
            self.validate()

    def test_non_frame_duration_and_two_minute_limit_are_rejected(self):
        original = copy.deepcopy(self.edl)
        self.edl["shots"][0]["duration"] = 0.501
        with self.assertRaisesRegex(ValueError, "exact number"):
            self.validate()
        self.edl = original
        self.edl["shots"][0]["duration"] = 59
        self.edl["shots"][3]["duration"] = 59
        with self.assertRaisesRegex(ValueError, "strictly under 120"):
            self.validate()

    def test_mismatched_run_cannot_pretend_to_be_simultaneous(self):
        self.edl["sources"]["tablet"]["run"] = "another-take"
        with self.assertRaisesRegex(ValueError, "same run and commit"):
            self.validate()

    def test_changed_timing_manifest_fails(self):
        (self.root / "synthetic-timing.json").write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
            self.validate()

    def test_native_commit_must_resolve_and_card_only_film_is_not_a_demo(self):
        self.edl["purpose"] = "submission-edit"
        for source in self.edl["sources"].values():
            source["kind"] = "native-recording"
        with self.assertRaisesRegex(ValueError, "full lowercase Git commit"):
            self.validate()
        self.edl["shots"] = [shot for shot in self.edl["shots"] if shot["kind"] == "card"]
        self.edl["sources"] = {}
        self.edl["timelines"] = {}
        with self.assertRaisesRegex(ValueError, "not only graphic cards"):
            self.validate()

    def test_existing_output_and_sidecars_are_never_overwritten(self):
        target = self.root / "existing.mp4"
        target.write_bytes(b"keep me")
        with self.assertRaisesRegex(ValueError, "Refusing to overwrite"):
            compose.render(self.edl_path, target)
        self.assertEqual(target.read_bytes(), b"keep me")
        sidecar = self.root / "new.mp4.manifest.json"
        sidecar.write_text("keep evidence", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Refusing to overwrite"):
            compose.render(self.edl_path, self.root / "new.mp4")


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg and ffprobe required")
class RenderTests(unittest.TestCase):
    def test_vfr_cuts_keep_held_frame_and_fractional_pair_offsets(self):
        with tempfile.TemporaryDirectory(prefix="meowwatch-vfr-synthetic-only-") as folder:
            root = Path(folder)
            edl_path = fixture(root)
            edl = compose.read_json(edl_path)
            for role, size in (("phone", "90x180"), ("tablet", "320x180")):
                path = root / f"vfr-{role}.mp4"
                graph = ";".join(f"color={color}:s={size}:r=10:d=0.1[v{i}]"
                                  for i, color in enumerate(("red", "lime", "blue", "yellow", "magenta")))
                graph += ";[v0][v1][v2][v3][v4]concat=n=5:v=1:a=0,settb=1/1000,"
                graph += "setpts='if(eq(N,0),0,if(eq(N,1),700,if(eq(N,2),1800,if(eq(N,3),2050,2900))))'[out]"
                subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-filter_complex_threads", "1",
                                "-filter_complex", graph, "-map", "[out]", "-fps_mode", "vfr", "-enc_time_base", "1:1000",
                                "-video_track_timescale", "1000", "-c:v", "libx264", "-bf", "0", "-threads", "1",
                                "-pix_fmt", "yuv420p", str(path)], check=True)
                frame_data = json.loads(subprocess.check_output([
                    "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_frames", "-show_entries",
                    "frame=best_effort_timestamp_time", "-of", "json", str(path)], text=True))
                self.assertEqual([float(f["best_effort_timestamp_time"]) for f in frame_data["frames"]],
                                 [0, 0.7, 1.8, 2.05, 2.9])
                edl["sources"][role].update({"path": path.name, "sha256": compose.sha256(path)})
            timing_path = root / "vfr-timing.json"
            timing = {"schemaVersion": 2, "sources": {}}
            for role, offset in (("phone", 0), ("tablet", 0.37)):
                timing["sources"][role] = {"segments": [{
                    "path": edl["sources"][role]["path"], "sha256": edl["sources"][role]["sha256"],
                    "status": "available", "estimatedStartSeconds": str(offset),
                    "estimatedEndSeconds": str(offset + 3)}], "recordingGaps": []}
            timing_path.write_text(json.dumps(timing), encoding="utf-8")
            edl["timelines"]["together"] = {"path": timing_path.name, "sha256": compose.sha256(timing_path)}
            edl["shots"] = [edl["shots"][1], edl["shots"][2]]
            edl["shots"][0].update({"in": 0.85, "out": 2.85})
            edl["shots"][1].update({"in": 2.15, "out": 2.95})
            edl_path.write_text(json.dumps(edl), encoding="utf-8")
            target = root / "synthetic-vfr.mp4"
            manifest = compose.render(edl_path, target, preset="ultrafast")
            self.assertAlmostEqual(manifest["output"]["probe"]["duration"], 2.8, places=5)
            # Sample every output frame. A normal player holds the source frame
            # whose PTS is the greatest timestamp <= the requested source clock.
            colors = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0), (255, 0, 255)]
            transitions = [0, 0.7, 1.8, 2.05, 2.9]
            for role, x, y, start, count, source_in in (
                ("phone", 320, 450, 0, 60, 0.85),
                ("tablet", 1200, 500, 0, 60, 0.48),
                ("single tail", 1300, 500, 60, 24, 2.15),
            ):
                pixels = subprocess.check_output([
                    "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(target),
                    "-vf", f"trim=start_frame={start}:end_frame={start+count},crop=2:2:{x}:{y}",
                    "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"])
                self.assertEqual(len(pixels), count * 12)
                for frame in range(count):
                    clock = source_in + frame / 30
                    expected = colors[max(i for i, t in enumerate(transitions) if t <= clock + 0.000001)]
                    actual = pixels[frame * 12:frame * 12 + 3]
                    self.assertTrue(all(abs(actual[c] - expected[c]) < 30 for c in range(3)),
                                    (role, frame, clock, expected, tuple(actual)))

    def test_synthetic_render_keeps_offsets_and_real_pixels_and_records_hashes(self):
        with tempfile.TemporaryDirectory(prefix="meowwatch-synthetic-only-") as folder:
            root = Path(folder)
            edl = fixture(root, real=True)
            before = {path: compose.sha256(path) for path in root.glob("synthetic-*.mp4")}
            target = root / "synthetic-not-a-demo.mp4"
            manifest = compose.render(edl, target, preset="ultrafast")
            self.assertEqual(manifest["acceptance"], "Synthetic fixture only")
            self.assertEqual(manifest["output"]["probe"]["duration"], 3)
            self.assertEqual(manifest["output"]["sha256"], compose.sha256(target))
            self.assertEqual(before, {path: compose.sha256(path) for path in before})
            frames = json.loads(subprocess.check_output([
                "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_frames",
                "-show_entries", "frame=color_space,color_range,color_primaries,color_transfer",
                "-of", "json", str(target)], text=True))["frames"]
            self.assertEqual(len(frames), 90)
            self.assertEqual({(f["color_space"], f["color_range"], f["color_primaries"], f["color_transfer"])
                              for f in frames}, {("bt709", "tv", "bt709", "bt709")})
            for when, x, y, color in ((0.65, 320, 450, 1), (0.65, 1200, 500, 0),
                                      (1.3, 1200, 500, 1), (1.8, 1300, 500, 2)):
                pixels = subprocess.check_output([
                    "ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", str(when), "-i", str(target),
                    "-frames:v", "1", "-vf", f"crop=2:2:{x}:{y}", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"])
                self.assertEqual(len(pixels), 12)
                self.assertGreater(pixels[color], 220)
                self.assertTrue(all(pixels[c] < 30 for c in range(3) if c != color), (when, pixels[:3]))
            self.assertTrue(target.with_suffix(".mp4.edl.json").is_file())
            self.assertTrue(target.with_suffix(".mp4.sha256").is_file())


if __name__ == "__main__":
    unittest.main(verbosity=2)
