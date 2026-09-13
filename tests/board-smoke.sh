#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Run on the ATK-DLRK3588 after booting the BSP kernel: checks the running
# release, the Rust character device, UART3 internal loopback over DMA at
# several baud rates, and prints the DMA counters. Needs root for binding and
# debugfs. External RS485 tests need a peer; see docs/rust-uart-rs485.rst.
set -euo pipefail
expected=${1:-}
rs485_test=${RS485_TEST:-/usr/local/bin/rs485-test}
bind=${BIND_UART3:-/usr/local/sbin/bind-uart3.sh}
[[ $EUID -eq 0 ]] || { echo 'Run as root on the development board.' >&2; exit 1; }
release=$(uname -r)
if [[ -n $expected && $release != "$expected" ]]; then
	echo "Running $release, expected $expected" >&2; exit 1
fi
echo "kernel: $(uname -a)"
echo "model: $(tr -d '\0' < /proc/device-tree/model)"

modprobe rust_chardev
[[ -c /dev/rust-chardev ]] || { echo 'no /dev/rust-chardev' >&2; exit 1; }
"$rs485_test" chardev --device /dev/rust-chardev

"$bind" --rust
readlink /sys/bus/platform/devices/feb60000.serial/driver
[[ -c /dev/ttyRU0 ]] || { echo 'no /dev/ttyRU0' >&2; exit 1; }
for baud in 9600 115200 460800 1500000; do
	timeout 60 "$rs485_test" loopback --device /dev/ttyRU0 --baud "$baud" --count 20 --size 512
done

mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug
cat /sys/kernel/debug/rust_dw_uart/dma
# 4096 (O) is expected: the Rust modules are built out of tree. Anything else set
# in the mask points at a real problem.
echo "tainted: $(cat /proc/sys/kernel/tainted) (4096 = out-of-tree modules only)"
dmesg | grep -iE 'rust_dw_uart|rust_chardev|oops|warning:' | tail -20 || true
echo ATK_DLRK3588_BSP_SMOKE_OK
