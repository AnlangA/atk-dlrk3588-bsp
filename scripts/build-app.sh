#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Cross-build the rs485-test application and the QEMU init program for the
# board. Host-side tests and lints live in scripts/check.sh.
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd cargo "$AARCH64_CC"

target=${CARGO_BUILD_TARGET:-aarch64-unknown-linux-gnu}
rustup target list --installed 2>/dev/null | grep -qx "$target" ||
	log "warning: rustup target $target not reported as installed; cargo will tell if it is missing"
export CARGO_TARGET_DIR=$APP_OUT
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=${CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER:-$AARCH64_CC}

cd "$BSP_ROOT/app/rs485-test" || die "missing app/rs485-test"
cargo build --locked --release --target "$target" --bins "$@"
log "application: $APP_OUT/$target/release/rs485-test"
log "QEMU init:   $APP_OUT/$target/release/driver-test-init"
