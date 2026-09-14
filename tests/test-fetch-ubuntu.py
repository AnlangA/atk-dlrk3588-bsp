#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Exercise Ubuntu fetching with local archives and the real curl/tar tools."""

import hashlib
import io
import os
from pathlib import Path
import shlex
import subprocess
import tarfile
import tempfile
import unittest


class UbuntuFetchTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bsp ubuntu test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.upstream = self.root / "upstream"
        self.upstream.mkdir()
        self.archive = self.upstream / "fixture.tar.gz"
        with tarfile.open(self.archive, "w:gz") as tar:
            member = tarfile.TarInfo("etc/os-release")
            data = b"ID=ubuntu\n"
            member.size = len(data)
            tar.addfile(member, io.BytesIO(data))
        self.expected = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.external = self.root / "external"
        self.cache = self.external / "ubuntu-base"
        self.config = self.root / "local.env"
        self.fetch = Path(__file__).resolve().parents[1] / "scripts/fetch.sh"

    def run_fetch(self):
        settings = {
            "UBUNTU_BASE_URL": self.upstream.as_uri(),
            "UBUNTU_BASE_ARCHIVE": self.archive.name,
            "UBUNTU_BASE_SHA256": self.expected,
        }
        self.config.write_text("".join(f"{k}={shlex.quote(v)}\n" for k, v in settings.items()))
        env = {**os.environ, "BSP_LOCAL_ENV": str(self.config),
               "BSP_EXTERNAL": str(self.external)}
        for name in ("UBUNTU_BASE_DIR", "BSP_LIB_LOADED"):
            env.pop(name, None)
        return subprocess.run([str(self.fetch), "ubuntu-base"], env=env,
                              capture_output=True, text=True)

    def test_download_extract_and_offline_reuse(self):
        first = self.run_fetch()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual((self.cache / "rootfs/etc/os-release").read_text(), "ID=ubuntu\n")
        cached = self.cache / self.archive.name
        before = cached.stat().st_mtime_ns
        self.archive.unlink()
        sentinel = self.cache / "rootfs/local-edit"
        sentinel.write_text("keep\n")
        second = self.run_fetch()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(cached.stat().st_mtime_ns, before)
        self.assertEqual(sentinel.read_text(), "keep\n")

    def test_checksum_failure_preserves_existing_cache(self):
        self.cache.mkdir(parents=True)
        cached = self.cache / self.archive.name
        cached.write_bytes(b"old cache")
        self.archive.write_bytes(b"bad download")
        result = self.run_fetch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum mismatch", result.stderr)
        self.assertEqual(cached.read_bytes(), b"old cache")
        self.assertFalse((self.cache / "rootfs").exists())
        self.assertFalse(list(self.cache.glob(".download.*")))

    def test_unmanaged_tree_is_preserved(self):
        tree = self.cache / "rootfs"
        tree.mkdir(parents=True)
        (tree / "local-edit").write_text("keep\n")
        result = self.run_fetch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("matching extraction stamp", result.stderr)
        self.assertEqual((tree / "local-edit").read_text(), "keep\n")

    def test_extraction_failure_leaves_no_partial_tree(self):
        self.archive.write_bytes(b"not a tar archive")
        self.expected = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        result = self.run_fetch()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.cache / "rootfs").exists())
        self.assertFalse((self.cache / ".rootfs.sha256").exists())
        self.assertFalse(list(self.cache.glob(".extract.*")))


if __name__ == "__main__":
    unittest.main()
