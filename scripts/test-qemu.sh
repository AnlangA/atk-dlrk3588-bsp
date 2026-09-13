#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Run tests/qemu-test.py with the paths and toolchain from lib.sh/local.env.
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd python3 readelf "$AARCH64_CC"
command -v "$QEMU" >/dev/null || [[ -x $QEMU ]] || die "QEMU not found: $QEMU (set QEMU in local.env)"
exec python3 "$BSP_ROOT/tests/qemu-test.py" "$@"
