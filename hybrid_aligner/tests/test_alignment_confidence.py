import importlib.util
import math
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    'alignment_confidence', Path(__file__).resolve().parents[1] / 'alignment_confidence.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
score = module.word_alignment_confidence


class AlignmentConfidenceTests(unittest.TestCase):
    def test_score_changes_with_acoustic_evidence(self):
        self.assertAlmostEqual(score([[math.log(0.9)]], [1], [0], 0, 1, [0]), 0.9)
        self.assertAlmostEqual(score([[math.log(0.2)]], [1], [0], 0, 1, [0]), 0.2)

    def test_blank_frames_do_not_inflate_confidence(self):
        probabilities = [[math.log(0.8), math.log(0.2)], [0, -100], [0, -100]]
        self.assertAlmostEqual(score(probabilities, [1, 2, 2], [1], 0, 1, [0, 1, 2]), 0.2)

    def test_letters_have_equal_weight_and_missing_letters_have_zero_support(self):
        probabilities = [[math.log(0.8), -100], [math.log(0.8), -100], [-100, math.log(0.4)]]
        self.assertAlmostEqual(score(probabilities, [1, 1, 3], [0, 1], 0, 2, [0, 1, 2]), 0.6)
        self.assertAlmostEqual(score(probabilities, [1, 1, 2], [0, 1], 0, 2, [0, 1, 2]), 0.4)

    def test_empty_tokens_are_unknown(self):
        self.assertIsNone(score([], [], [], 0, 0, []))


if __name__ == '__main__':
    unittest.main()
