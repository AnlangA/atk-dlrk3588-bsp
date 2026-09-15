#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Add a display DTB entry while reusing a known-working kernel and rootfs."""
import argparse
import os
from pathlib import Path
import re
import shutil
import struct
import tempfile

DTB_PATH = "/atk-slint/rk3588-atk-dlrk3588.dtb"


def add_entry(text, base_label):
    if base_label == "slint" or not re.fullmatch(r"[A-Za-z0-9_-]+", base_label):
        raise ValueError("choose an existing non-slint base label")
    blocks = re.split(r"(?im)^(?=LABEL\s)", text)
    entries = {}
    for block in blocks[1:]:
        label = block.splitlines()[0].split()[1]
        if label in entries:
            raise ValueError(f"duplicate LABEL {label}")
        entries[label] = block
    if base_label not in entries:
        raise ValueError(f"missing base LABEL {base_label}")
    base = entries[base_label]
    for keyword in ("LINUX", "FDT", "APPEND"):
        if len(re.findall(rf"(?im)^\s*{keyword}\s+\S.*$", base)) != 1:
            raise ValueError(f"base entry needs exactly one {keyword}")
    if re.search(r"(?im)^\s*FDTOVERLAYS\s", base):
        raise ValueError("base entry has overlays; review its display configuration manually")
    header = blocks[0]
    if len(re.findall(r"(?im)^DEFAULT\s+\S+.*$", header)) != 1:
        raise ValueError("expected one global DEFAULT")
    header = re.sub(r"(?im)^DEFAULT\s+\S+.*$", "DEFAULT slint", header)
    entry = re.sub(r"(?im)^LABEL\s+.*$", "LABEL slint", base)
    entry = re.sub(r"(?im)^\s*MENU LABEL[^\n]*", "    MENU LABEL Ubuntu - Slint DRM display", entry)
    entry = re.sub(r"(?im)^\s*FDT\s+[^\n]*", f"    FDT {DTB_PATH}", entry)
    preserved = [block for label, block in entries.items() if label != "slint"]
    return header + "".join(preserved).rstrip() + "\n\n" + entry.strip() + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dtb", type=Path)
    parser.add_argument("--base-label", required=True)
    parser.add_argument("--check", action="store_true", help="print candidate config without writing")
    args = parser.parse_args()
    config = Path("/boot/extlinux/extlinux.conf")
    updated = add_entry(config.read_text(), args.base_label)
    data = args.dtb.read_bytes()
    if len(data) < 40 or struct.unpack_from(">II", data) != (0xD00DFEED, len(data)):
        raise ValueError("not a complete flattened device tree")
    if args.check:
        print(updated, end="")
        return
    if os.geteuid() != 0:
        raise PermissionError("run as root")
    destination = Path("/boot") / DTB_PATH.lstrip("/")
    backup = Path(tempfile.mkdtemp(prefix="slint-boot.", dir="/var/backups"))
    shutil.copy2(config, backup / "extlinux.conf")
    if destination.exists():
        shutil.copy2(destination, backup / "previous.dtb")
    destination.parent.mkdir(exist_ok=True)
    temporary_dtb = destination.with_suffix(".dtb.new")
    temporary_dtb.write_bytes(data)
    temporary_dtb.chmod(0o644)
    os.replace(temporary_dtb, destination)
    temporary_config = config.with_suffix(".conf.new")
    temporary_config.write_text(updated)
    temporary_config.chmod(0o644)
    os.replace(temporary_config, config)
    os.sync()
    print(f"Display DTB installed. Backup: {backup}")
    print(f"Reboot to test; original '{args.base_label}' entry remains available.")
    print(f"Restore default: cp {backup}/extlinux.conf {config}")


if __name__ == "__main__":
    main()
