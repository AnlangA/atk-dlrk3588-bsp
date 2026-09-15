#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# A linker wrapper avoids putting a shell command into Cargo's linker path.
set -euo pipefail
: "${DISPLAY_SYSROOT:?set DISPLAY_SYSROOT to the ARM64 sysroot}"
: "${AARCH64_CC:?set AARCH64_CC to the cross compiler}"
exec "$AARCH64_CC" --sysroot="$DISPLAY_SYSROOT" \
	-B"$DISPLAY_SYSROOT/usr/lib/aarch64-linux-gnu/" \
	-Wl,-rpath-link,"$DISPLAY_SYSROOT/usr/lib/aarch64-linux-gnu" "$@"
