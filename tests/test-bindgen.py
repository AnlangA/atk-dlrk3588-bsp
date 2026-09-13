#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Check the bindgen process boundary without a kernel tree or toolchain."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class BindgenEnvironmentTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bsp bindgen test ")
        self.addCleanup(self.temp.cleanup)
        self.backend = Path(self.temp.name) / "fake bindgen"
        self.backend.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "print(json.dumps({'log': os.environ.get('RUST_LOG'), "
            "'libclang': os.environ.get('LIBCLANG_PATH'), 'args': sys.argv[1:]}))\n"
            "if '--fail' in sys.argv:\n"
            "    print('fatal error: missing header', file=sys.stderr)\n"
            "    sys.exit(23)\n"
        )
        self.backend.chmod(0o755)
        self.wrapper = Path(__file__).resolve().parents[1] / "scripts/bindgen.sh"
        self.env = {
            **os.environ,
            "BSP_BINDGEN_BIN": str(self.backend),
            "RUST_LOG": "warn",
            "LIBCLANG_PATH": "/toolchain path/lib",
        }
        self.env.pop("BINDGEN_RUST_LOG", None)

    def run_bindgen(self, *args):
        result = subprocess.run(
            [str(self.wrapper), *args], env=self.env, capture_output=True, text=True
        )
        return result, json.loads(result.stdout)

    def test_host_logging_does_not_leak(self):
        result, data = self.run_bindgen("header with spaces.h", "--", "-DVALUE=1")
        self.assertEqual(result.returncode, 0)
        self.assertIsNone(data["log"])
        self.assertEqual(data["libclang"], "/toolchain path/lib")
        self.assertEqual(data["args"], ["header with spaces.h", "--", "-DVALUE=1"])
        self.assertEqual(self.env["RUST_LOG"], "warn")

    def test_explicit_parser_logging(self):
        self.env["BINDGEN_RUST_LOG"] = "bindgen=debug"
        result, data = self.run_bindgen("--version")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(data["log"], "bindgen=debug")
        self.assertEqual(data["args"], ["--version"])

    def test_empty_explicit_filter(self):
        self.env["BINDGEN_RUST_LOG"] = ""
        result, data = self.run_bindgen()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(data["log"], "")

    def test_diagnostics_and_failure_are_preserved(self):
        result, _ = self.run_bindgen("--fail")
        self.assertEqual(result.returncode, 23)
        self.assertEqual(result.stderr, "fatal error: missing header\n")


if __name__ == "__main__":
    unittest.main()
