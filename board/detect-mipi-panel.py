#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Read the ATK MIPI ID resistor through the mainline SARADC IIO ABI."""
import json
from pathlib import Path
import statistics
import sys
import time

# Alientek DLRK3588 quick-start manual, section 3.3. Vendor resource_hwid.c
# uses an absolute tolerance of 100 on the RK3588's 12-bit ADC sample.
PANELS = {
    0: ("5p5-720x1280", 720, 1280, "gt911"),
    1410: ("5p5-1080x1920", 1080, 1920, "gt911"),
    2748: ("10p1-800x1280", 800, 1280, "gt928"),
}


def identify(samples):
    if not samples or any(value < 0 or value > 4095 for value in samples):
        raise ValueError("invalid 12-bit SARADC samples")
    if max(samples) - min(samples) > 100:
        raise ValueError("unstable panel ID; check the ribbon cable")
    raw = int(statistics.median(samples))
    matches = [(value, panel) for value, panel in PANELS.items() if abs(value - raw) <= 100]
    if len(matches) != 1:
        raise ValueError(f"unknown/unconnected panel ID {raw}; no profile selected")
    expected, (profile, width, height, touch) = matches[0]
    return dict(profile=profile, width=width, height=height, touch=touch,
                adc_channel=7, adc_expected=expected, adc_raw=raw, samples=samples)


def main():
    paths = []
    for device in Path("/sys/bus/iio/devices").glob("iio:device*"):
        compatible = device / "of_node/compatible"
        if compatible.exists() and b"rockchip,rk3588-saradc\0" in compatible.read_bytes():
            paths.append(device / "in_voltage7_raw")
    if len(paths) != 1:
        raise ValueError("expected one RK3588 SARADC; enable &saradc and its vref-supply")
    samples = []
    for _ in range(9):
        samples.append(int(paths[0].read_text()))
        time.sleep(0.02)
    result = identify(samples)
    result["iio_path"] = str(paths[0])
    # Both sockets share ADC7. It identifies one attached panel, not its port.
    result["port"] = "not encoded by the ID resistor; check I2C5/I2C6 touch presence"
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"panel detection: {error}", file=sys.stderr)
        sys.exit(1)
