#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# TAP runner (formerly tools/testing/selftests/rust_uart_rs485/run.sh).
# Uses rs485-test from RS485_TEST, next to this script, or PATH.
# RS485_DEVICE=/dev/ttyRU0 enables the UART round trip after a peer is running.
set -u
cd "$(dirname "$0")" || exit 1
if [ -n "${RS485_TEST:-}" ]; then
	app=$RS485_TEST
elif [ -x ./rs485-test ]; then
	app=./rs485-test
else
	app=$(command -v rs485-test 2>/dev/null || true)
fi
echo 'TAP version 13'
echo '1..2'
if [ -z "$app" ] || [ ! -x "$app" ]; then
	echo 'ok 1 - Rust character device # SKIP build the Rust application first'
	echo 'ok 2 - UART/RS485 round trip # SKIP build the Rust application first'
	exit 4
fi
ran=0
failed=0
if [ -c /dev/rust-chardev ]; then
	ran=1
	if output=$("$app" chardev 2>&1); then
		printf '%s\n' "$output" | sed 's/^/# /'
		echo 'ok 1 - Rust character device'
	else
		printf '%s\n' "$output" | sed 's/^/# /'
		echo 'not ok 1 - Rust character device'
		failed=1
	fi
else
	echo 'ok 1 - Rust character device # SKIP load rust_chardev first'
fi
if [ -n "${RS485_DEVICE:-}" ]; then
	ran=1
	if output=$("$app" uart --device "$RS485_DEVICE" \
		--baud "${RS485_BAUD:-115200}" --count "${RS485_COUNT:-100}" 2>&1); then
		printf '%s\n' "$output" | sed 's/^/# /'
		echo 'ok 2 - UART/RS485 round trip'
	else
		printf '%s\n' "$output" | sed 's/^/# /'
		echo 'not ok 2 - UART/RS485 round trip'
		failed=1
	fi
else
	echo 'ok 2 - UART/RS485 round trip # SKIP set RS485_DEVICE after starting a peer'
fi
[ "$failed" -eq 0 ] || exit 1
[ "$ran" -ne 0 ] || exit 4
exit 0
