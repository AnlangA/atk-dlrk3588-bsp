#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("display_boot", Path(__file__).resolve().parents[1] / "board/install-display-dtb.py")
boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot)

BASE = """DEFAULT rust
TIMEOUT 30

LABEL rust
    MENU LABEL Working kernel
    LINUX /rust/Image
    FDT /rust/board.dtb
    APPEND console=ttyS2,1500000 root=/dev/mmcblk0p2 ro

LABEL rescue
    LINUX /Image
    FDT /board.dtb
    APPEND root=/dev/mmcblk0p2 ro
"""


class DisplayBoot(unittest.TestCase):
    def test_preserves_working_entries_and_reuses_kernel(self):
        updated = boot.add_entry(BASE, "rust")
        self.assertIn(BASE[BASE.index("LABEL rust"):].rstrip(), updated)
        display = updated.split("LABEL slint\n")[1]
        self.assertIn("LINUX /rust/Image", display)
        self.assertIn("console=ttyS2,1500000 root=/dev/mmcblk0p2 ro", display)
        self.assertIn("FDT /atk-slint/rk3588-atk-dlrk3588.dtb", display)
        self.assertEqual(updated.count("DEFAULT slint"), 1)

    def test_reinstall_is_idempotent(self):
        once = boot.add_entry(BASE, "rust")
        self.assertEqual(boot.add_entry(once, "rust"), once)

    def test_rejects_ambiguous_or_incomplete_boot_config(self):
        for text, label in [(BASE, "missing"), (BASE, "slint"),
                            (BASE + "LABEL rust\n", "rust"),
                            (BASE.replace("FDT /rust/board.dtb", "# FDT omitted"), "rust"),
                            (BASE.replace("TIMEOUT 30", "DEFAULT rescue"), "rust")]:
            with self.subTest(text=text, label=label), self.assertRaises(ValueError):
                boot.add_entry(text, label)


if __name__ == "__main__":
    unittest.main()
