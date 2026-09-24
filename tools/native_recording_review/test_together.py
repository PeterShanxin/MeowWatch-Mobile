import unittest

from tools.native_recording_review.together import picture_timing, review_indices


class PictureTimingTests(unittest.TestCase):
    def test_preserves_sparse_variable_picture_clock(self):
        pts, timing = picture_timing({'frames': [
            {'best_effort_timestamp_time': value} for value in ('0.2', '0.3', '1.1', '1.2')
        ]})
        self.assertEqual(pts, [.2, .3, 1.1, 1.2])
        self.assertAlmostEqual(timing['maxPictureGapSeconds'], .8)
        self.assertEqual(timing['gapsOverHalfSecond'], 1)
        self.assertEqual(timing['longestGaps'][0]['afterFrameIndex'], 1)
        self.assertAlmostEqual(timing['meanPicturesPerSecond'], 3)

    def test_rejects_missing_unordered_or_nonfinite_pictures(self):
        for values in ([], ['0'], ['0', '0'], ['1', '0'], ['0', 'NaN'], ['0', 'Infinity']):
            with self.subTest(values=values), self.assertRaises(ValueError):
                picture_timing({'frames': [{'best_effort_timestamp_time': v} for v in values]})
        with self.assertRaises(KeyError):
            picture_timing({'frames': [{}]})

    def test_editorial_samples_retain_the_held_vfr_picture(self):
        pts, timing = picture_timing({'frames': [
            {'best_effort_timestamp_time': value}
            for value in (0, 1, 2, 3.9, 4.2, 5, 6, 7.8, 8.3, 9, 10)
        ]})
        indices = review_indices(pts, timing)
        self.assertIn(3, indices)  # 3.9 is still on screen at second 4.
        self.assertIn(7, indices)  # 7.8 is still on screen at second 8.
        self.assertEqual(indices, sorted(set(indices)))

    def test_editorial_samples_are_bounded_and_keep_both_ends(self):
        pts, timing = picture_timing({'frames': [
            {'best_effort_timestamp_time': value} for value in range(10000)
        ]})
        indices = review_indices(pts, timing)
        self.assertLessEqual(len(indices), 54)
        self.assertEqual(indices[0], 0)
        self.assertEqual(indices[-1], 9999)


if __name__ == '__main__':
    unittest.main()
