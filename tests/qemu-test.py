#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Boot the built kernel in QEMU and run the real ARM64 module lifecycle tests.

A throwaway initramfs is assembled from driver-test-init, rs485-test, the two
out-of-tree modules and the cross toolchain's C runtime. QEMU virt has no
RK3588 UART or PL330, so this covers module load/unload and the character
device, not the physical controller.
"""

import argparse
import gzip
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys


def output(*args):
    # readelf output is parsed with English patterns; a localized host must not break that.
    env = {**os.environ, "LC_ALL": "C"}
    return subprocess.check_output(args, text=True, env=env).strip()


def archive(entries):
    result = bytearray()
    for ino, (name, mode, data) in enumerate(entries, 1):
        encoded = name.encode() + b"\0"
        fields = [ino, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(encoded), 0]
        result += b"070701" + b"".join(f"{value:08x}".encode() for value in fields)
        result += encoded
        result += b"\0" * (-len(result) % 4)
        result += data
        result += b"\0" * (-len(result) % 4)
    return bytes(result)


def main():
    root = Path(__file__).resolve().parents[1]
    build = Path(os.environ.get("BSP_BUILD", root / "build"))
    env = os.environ.get
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", type=Path,
                        default=Path(env("LINUX_OUT", build / "linux")) / "arch/arm64/boot/Image")
    parser.add_argument("--modules-dir", type=Path,
                        default=Path(env("LINUX_MODULES_OUT", build / "linux-modules")))
    parser.add_argument("--app-dir", type=Path,
                        default=Path(env("APP_OUT", build / "app")) / "aarch64-unknown-linux-gnu/release")
    parser.add_argument("--output-dir", type=Path, default=build / "qemu")
    parser.add_argument("--cc", default=env("AARCH64_CC", "aarch64-linux-gnu-gcc"))
    parser.add_argument("--qemu", default=env("QEMU", "qemu-system-aarch64"))
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()

    sysroot = Path(output(args.cc, "-print-sysroot"))
    entries = [(name, stat.S_IFDIR | 0o755, b"") for name in ("dev", "proc", "lib")]
    # GNU cross toolchains may build their loader with /lib64 as its search path.
    entries.append(("lib64", stat.S_IFLNK | 0o777, b"lib"))
    files = {
        "init": args.app_dir / "driver-test-init",
        "rs485-test": args.app_dir / "rs485-test",
        "rust_chardev.ko": args.modules_dir / "rust_chardev.ko",
        "rust_dw_uart.ko": args.modules_dir / "rust_dw_uart.ko",
    }
    for name, path in files.items():
        if not path.is_file():
            raise SystemExit(f"missing {name}: {path} (build the kernel, modules and app first)")
    pending = [files["init"], files["rs485-test"]]
    for binary in pending.copy():
        program = output("readelf", "-l", str(binary))
        interpreter = re.search(r"Requesting program interpreter: ([^\]]+)", program)
        if interpreter:
            target = interpreter.group(1).lstrip("/")
            source = sysroot / target
            if not source.exists():
                source = sysroot / "lib64" / Path(target).name
            if not source.is_file():
                raise RuntimeError(f"Cannot locate ELF interpreter {target} in {sysroot}")
            files[target] = source
    seen = set()
    while pending:
        binary = pending.pop()
        for name in re.findall(r"Shared library: \[([^\]]+)\]", output("readelf", "-d", str(binary))):
            if name in seen:
                continue
            seen.add(name)
            source = Path(output(args.cc, f"-print-file-name={name}"))
            if not source.is_file():
                candidates = (sysroot / "lib64", sysroot / "lib", sysroot / "usr/lib64", sysroot / "usr/lib")
                source = next((p / name for p in candidates if (p / name).is_file()), None)
            if source is None:
                raise RuntimeError(f"Cannot locate target runtime library {name}")
            files["lib/" + name] = source
            pending.append(source)
    for name, path in files.items():
        entries.append((name, stat.S_IFREG | 0o755, path.read_bytes()))
    entries.append(("TRAILER!!!", 0, b""))

    args.output_dir.mkdir(parents=True, exist_ok=True)
    initramfs = args.output_dir / "rust-test-initramfs.cpio.gz"
    initramfs.write_bytes(gzip.compress(archive(entries), mtime=0))
    qemu = shutil.which(args.qemu) or args.qemu
    command = [qemu, "-machine", "virt", "-cpu", "cortex-a53", "-m", "1024", "-smp", "2",
               "-nographic", "-nodefaults", "-serial", "stdio", "-monitor", "none", "-no-reboot",
               "-kernel", str(args.kernel), "-initrd", str(initramfs),
               "-append", "console=ttyAMA0 rdinit=/init panic=-1 loglevel=5"]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=args.timeout, check=False)
    log = args.output_dir / "qemu-test.log"
    log.write_bytes(result.stdout)
    print(result.stdout.decode(errors="replace"))
    print(f"QEMU log: {log}")
    if result.returncode or b"RUST_DRIVER_QEMU_RESULT=PASS" not in result.stdout:
        return 1
    if b"RUST_DRIVER_QEMU_RESULT=FAIL" in result.stdout:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
