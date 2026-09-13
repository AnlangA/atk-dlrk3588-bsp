#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the rs485-test application and the QEMU init program. Needs only
# cargo, the rustup target and a linker for that target; no kernel or U-Boot
# checkout is involved. Host-side tests and lints live in scripts/check.sh.
#   CARGO_BUILD_TARGET  Rust target (default aarch64-unknown-linux-gnu for the board)
#   AARCH64_CC          cross GCC used as the linker when cross-compiling
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd cargo

target=${CARGO_BUILD_TARGET:-aarch64-unknown-linux-gnu}
if [[ $target == aarch64-unknown-linux-gnu && $(uname -m) != aarch64 ]]; then
	export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=${CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER:-$AARCH64_CC}
	command -v "$CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER" >/dev/null ||
		die "cross linker not found: $CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER (set AARCH64_CC in local.env)"
fi
if command -v rustup >/dev/null && ! rustup target list --installed 2>/dev/null | grep -qx "$target"; then
	log "warning: rustup target $target is not installed; run: rustup target add $target"
fi
export CARGO_TARGET_DIR=$APP_OUT

cd "$BSP_ROOT/app/rs485-test" || die "missing app/rs485-test"
cargo build --locked --release --target "$target" --bins "$@"
log "application: $APP_OUT/$target/release/rs485-test"
log "QEMU init:   $APP_OUT/$target/release/driver-test-init"
