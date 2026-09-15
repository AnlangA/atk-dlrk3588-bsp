#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("panel_id", Path(__file__).resolve().parents[1] / "board/detect-mipi-panel.py")
panel_id = importlib.util.module_from_spec(spec)
spec.loader.exec_module(panel_id)


class PanelId(unittest.TestCase):
    def test_supported_panels_and_measurement_noise(self):
        for value, profile in [(3, "5p5-720x1280"), (1400, "5p5-1080x1920"), (2740, "10p1-800x1280")]:
            self.assertEqual(panel_id.identify([value, value + 2, value + 1])["profile"], profile)

    def test_unknown_unplugged_and_unstable_are_not_guessed(self):
        for samples in [[], [-1], [4096], [4095], [800], [1410, 2748]]:
            with self.subTest(samples=samples), self.assertRaises(ValueError):
                panel_id.identify(samples)


if __name__ == "__main__":
    unittest.main()
