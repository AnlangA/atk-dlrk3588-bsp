#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Check the actual Mali context, GPU jobs, scanout and optional evdev UI input."""
import argparse
import contextlib
import json
import mmap
import os
from pathlib import Path
import re
import signal
import struct
import subprocess
import time
import zlib


def command(*args):
    return subprocess.check_output(args, text=True)


def service():
    text = command("systemctl", "show", "slint-dashboard", "-p", "MainPID",
                   "-p", "ActiveState", "-p", "SubState", "-p", "InvocationID")
    return dict(line.split("=", 1) for line in text.splitlines())


def journal(invocation):
    return command("journalctl", f"_SYSTEMD_INVOCATION_ID={invocation}",
                   "--no-pager", "-o", "cat")


def gpu_time(pid):
    clients = {}
    for path in Path(f"/proc/{pid}/fdinfo").iterdir():
        values = dict(line.split(":", 1) for line in path.read_text().splitlines() if ":" in line)
        if values.get("drm-driver", "").strip() != "panthor":
            continue
        clients[values["drm-client-id"].strip()] = int(values.get("drm-engine-panthor", "0").split()[0])
    return sum(clients.values())


def panel_status():
    path = Path("/sys/kernel/debug/fde20000.dsi.0/status")
    def read():
        return {key: bytes.fromhex(value) for key, value in
                (line.split(":", 1) for line in path.read_text().splitlines())}
    # Error reads acknowledge historical errors. Check a fresh interval as well.
    read()
    time.sleep(0.1)
    values = read()
    assert values["display-id"] == bytes.fromhex("83 99 0c"), "unexpected DSI panel"
    assert values["power"][0] & 0x9c == 0x9c, "panel power/display state is not ready"
    assert values["pixel-format"] == b"\x77", "panel is not configured for RGB888"
    assert values["self-diagnostic"][0] & 0xc0 == 0xc0, "panel self-diagnostic failed"
    status = int.from_bytes(values["status"], "big")
    assert status & 0x80730401 == 0x80730400, "panel reports an inactive display or DSI error"
    errors = [values[f"dsi-errors-{i}"][0] for i in (1, 2)]
    assert errors == [0, 0], f"DSI receive errors: {errors}"
    scanlines = [int.from_bytes(values[f"scanline-{i}"], "big") for i in (1, 2)]
    # Reads pause DSI video at a frame boundary, so identical scanlines are
    # expected. They are recorded, not used as evidence of visible pixels.
    with open("/dev/mem", "rb", buffering=0) as memory:
        with mmap.mmap(memory.fileno(), 4096, flags=mmap.MAP_SHARED,
                       prot=mmap.PROT_READ, offset=0xfde20000) as registers:
            mode = struct.unpack_from("<I", registers, 0x1c)[0]
    assert mode == 3, "DSI video mode was not restored after panel reads"
    return dict(id=values["display-id"].hex(), status=f"{status:08x}",
                dsi_errors=errors, scanlines=scanlines, host_mode=mode,
                rgb_readback_raw="".join(values[name].hex() for name in ("red", "green", "blue")))


def png_info(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "missing PNG signature"
    assert data[-12:] == b"\0\0\0\0IEND\xaeB`\x82", "incomplete PNG"
    width, height, depth, colour = struct.unpack_from(">IIBB", data, 16)
    assert (width, height, depth, colour) == (1080, 1920, 8, 6), "unexpected capture format"
    offset = 8
    compressed = bytearray()
    while offset < len(data):
        length, kind = struct.unpack_from(">I4s", data, offset)
        payload = data[offset + 8:offset + 8 + length]
        if kind == b"IDAT":
            compressed.extend(payload)
        offset += 12 + length
    pixels = zlib.decompress(compressed)
    assert len(pixels) == (width * 4 + 1) * height
    assert len(set(pixels)) > 32, "GPU readback is blank or uniformly coloured"
    return dict(width=width, height=height, bytes=len(data))


def touch(device, x, y, tracking_id):
    def write(events):
        with device.open("wb", buffering=0) as output:
            for typ, code, value in events:
                output.write(struct.pack("@llHHi", 0, 0, typ, code, value))
    # Standard evdev injection into the explicitly identified Goodix device.
    write([(3, 0x2f, 0), (3, 0x39, tracking_id), (3, 0x35, x), (3, 0x36, y),
           (3, 0, x), (3, 1, y), (1, 0x14a, 1), (0, 0, 0)])
    time.sleep(0.1)
    write([(3, 0x2f, 0), (3, 0x39, -1), (1, 0x14a, 0), (0, 0, 0)])
    # Leave enough time between taps for libinput's touch debouncing.
    time.sleep(0.7)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--touch", action="store_true", help="inject Count/Pause/Reset clicks; resets UI state")
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise PermissionError("run as root for profiling and process inspection")
    info = service()
    assert info["ActiveState"] == "active" and info["SubState"] == "running"
    pid = int(info["MainPID"])
    logs = journal(info["InvocationID"])
    assert "GPU_READY: vendor=Mesa; renderer=Mali-G610" in logs
    assert "GPU_SCANOUT:" in logs and "GPU_FRAME:" in logs
    status = Path(f"/proc/{pid}/status").read_text()
    assert int(re.search(r"^Uid:\s+(\d+)", status, re.M)[1]) != 0
    assert "CapEff:\t0000000000000000" in status
    taint = int(Path("/proc/sys/kernel/tainted").read_text())
    assert taint & ~(1 << 12) == 0, f"unexpected kernel taint: {taint}"

    clock = Path("/sys/kernel/debug/clk/clk_dsihost0")
    dsi_clock = dict(parent=(clock / "clk_parent").read_text().strip(),
                     rate_hz=int((clock / "clk_rate").read_text()))
    assert dsi_clock == dict(parent="cpll", rate_hz=375000000), \
        f"DSI system clock differs from the working J23 configuration: {dsi_clock}"

    capture = Path("/run/slint-dashboard/frame.png")
    old_time = capture.stat().st_mtime_ns if capture.exists() else 0
    profiling = Path("/sys/bus/platform/devices/fb000000.gpu/profiling")
    previous = profiling.read_text()
    try:
        profiling.write_text("3\n")
        before = gpu_time(pid)
        # A paused dashboard is healthy and need not render periodically.
        # SIGUSR1 explicitly requests a GPU frame without changing UI state.
        os.kill(pid, signal.SIGUSR1)
        time.sleep(5)
        after = gpu_time(pid)
        assert after > before, "no measured GPU execution after an explicit redraw request"
    finally:
        with contextlib.suppress(OSError):
            profiling.write_text(previous)

    states = [p.read_text() for p in Path("/sys/kernel/debug/dri").glob("*/state")]
    assert any("allocated by = slint-dashboard" in text and "modifier=0x800000000000" in text for text in states), "no AFBC scanout"
    registers = Path("/sys/kernel/debug/dri/display-subsystem/vop2/active_regs").read_text()
    prescan_match = re.search(r"^fdd90f30:\s+([0-9a-fA-F]+)", registers, re.M)
    assert prescan_match, "VP3 prescan register is unavailable"
    prescan_hsync = int(prescan_match[1], 16) & 0x1fff
    assert prescan_hsync >= 8, "RK3588 prescan sync interval is below eight pixels"
    for _ in range(50):
        time.sleep(0.2)
        try:
            if capture.stat().st_mtime_ns > old_time:
                screenshot = png_info(capture)
                break
        except (OSError, AssertionError, zlib.error):
            pass
    else:
        raise RuntimeError("no complete GPU screenshot after SIGUSR1")

    if args.touch:
        devices = [Path("/dev/input") / p.name for p in Path("/sys/class/input").glob("event*")
                   if (p / "device/name").read_text().strip() == "Goodix Capacitive TouchScreen"]
        assert len(devices) == 1, "expected one Goodix touch device"
        actions_before = journal(info["InvocationID"])
        pause_states = re.findall(r"^UI_ACTION:.*paused=(true|false)$", actions_before, re.M)
        if pause_states and pause_states[-1] == "true":
            touch(devices[0], 200, 1730, 99)
            resumed = journal(info["InvocationID"])[len(actions_before):]
            assert re.search(r"^UI_ACTION: pause; count=\d+; paused=false$", resumed, re.M), resumed
        start = len(journal(info["InvocationID"]))
        for tracking, (x, y) in enumerate([(870, 1730), (540, 1730), (200, 1730),
                                           (200, 1730), (870, 1730)], start=100):
            touch(devices[0], x, y, tracking)
        actions = journal(info["InvocationID"])[start:]
        assert "UI_ACTION: count; count=1; paused=false" in actions, actions
        assert "UI_ACTION: pause; count=1; paused=true" in actions, actions
        assert "UI_ACTION: pause; count=1; paused=false" in actions, actions
        assert "UI_ACTION: reset; count=0; paused=false" in actions, actions

    assert service()["MainPID"] == str(pid), "service restarted during validation"
    panel = panel_status()
    print(json.dumps(dict(result="PASS", renderer="Mali-G610 MC4 (Panfrost)",
                         scope="gpu_kms_panel_control", visible_image_verified=False,
                         gpu_execution_ns=after - before, gpu_redraw_requested=True,
                         screenshot=screenshot,
                         synthetic_touch=args.touch, panel=panel,
                         dsi_clock=dsi_clock,
                         prescan_hsync=prescan_hsync, pid=pid, kernel_taint=taint), indent=2))


if __name__ == "__main__":
    main()
