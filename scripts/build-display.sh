#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Cross build with target libraries copied from the board by display-sysroot.sh.
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd cargo pkg-config
target=${CARGO_BUILD_TARGET:-aarch64-unknown-linux-gnu}
export CARGO_TARGET_DIR=${DISPLAY_OUT:-$BSP_BUILD/slint}
if [[ $target == aarch64-unknown-linux-gnu && $(uname -m) != aarch64 ]]; then
	export DISPLAY_SYSROOT=${DISPLAY_SYSROOT:-$BSP_BUILD/slint-sysroot}
	[[ -f $DISPLAY_SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig/libseat.pc ]] ||
		die "missing target sysroot; run make display-sysroot"
	export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=$BSP_ROOT/scripts/display-linker.sh
	# Target-scoped variables leave build.rs and host font discovery on the host.
	export PKG_CONFIG_SYSROOT_DIR_aarch64_unknown_linux_gnu=$DISPLAY_SYSROOT
	export PKG_CONFIG_LIBDIR_aarch64_unknown_linux_gnu=$DISPLAY_SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig:$DISPLAY_SYSROOT/usr/share/pkgconfig
	export PKG_CONFIG_PATH_aarch64_unknown_linux_gnu=
	need_cmd "$AARCH64_CC"
fi
cargo build --manifest-path "$BSP_ROOT/app/slint-dashboard/Cargo.toml" \
	--locked --release --target "$target" -j "$JOBS" "$@"
log "display: $CARGO_TARGET_DIR/$target/release/slint-dashboard"
