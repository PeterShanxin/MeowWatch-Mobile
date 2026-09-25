import unittest

from tools.native_recording_review.purchase import sample_indices


class PurchaseSamplingTests(unittest.TestCase):
    def test_holds_original_picture_at_requested_time(self):
        # At 4s the source still displays the 3.8s picture, not the 4.1s one.
        self.assertEqual(sample_indices([0, 3.8, 4.1, 7.9, 8.1, 9]), [0, 1, 3, 5])

    def test_retains_short_segment_without_inventing_extra_frames(self):
        self.assertEqual(sample_indices([0.2, 0.3, 1.1]), [0, 2])

    def test_rejects_invalid_or_unbounded_timing(self):
        for pts in ([], [0], [0, 0], [1, 0], [0, float('nan')], [0, 76]):
            with self.subTest(pts=pts), self.assertRaises(ValueError):
                sample_indices(pts)


if __name__ == '__main__':
    unittest.main()
