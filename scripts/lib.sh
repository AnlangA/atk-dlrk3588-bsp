#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Shared settings for the atk-dlrk3588-bsp scripts. Source, do not execute.
[[ -n ${BSP_LIB_LOADED:-} ]] && return 0
BSP_LIB_LOADED=1
set -euo pipefail

BSP_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export BSP_ROOT

# shellcheck source=../manifest.env
source "$BSP_ROOT/manifest.env"
# Host-specific overrides (toolchain paths, board address). Never committed.
BSP_LOCAL_ENV=${BSP_LOCAL_ENV:-$BSP_ROOT/local.env}
if [[ -f $BSP_LOCAL_ENV ]]; then
	# Export everything so PATH, LIBCLANG_PATH, BL31 etc. reach make and cargo.
	set -a
	# shellcheck source=/dev/null
	source "$BSP_LOCAL_ENV"
	set +a
fi

BSP_EXTERNAL=${BSP_EXTERNAL:-$BSP_ROOT/external}
BSP_BUILD=${BSP_BUILD:-$BSP_ROOT/build}
LINUX_SRC=${LINUX_SRC:-$BSP_EXTERNAL/linux}
UBOOT_SRC=${UBOOT_SRC:-$BSP_EXTERNAL/u-boot}
RKBIN_DIR=${RKBIN_DIR:-$BSP_EXTERNAL/rkbin}
UBUNTU_BASE_DIR=${UBUNTU_BASE_DIR:-$BSP_EXTERNAL/ubuntu-base}
UBUNTU_BASE_LOCAL=${UBUNTU_BASE_LOCAL:-$BSP_ROOT/local/ubuntu-base}
LINUX_OUT=${LINUX_OUT:-$BSP_BUILD/linux}
LINUX_MODULES_OUT=${LINUX_MODULES_OUT:-$BSP_BUILD/linux-modules}
LINUX_DTS_OUT=${LINUX_DTS_OUT:-$BSP_BUILD/linux-dts}
UBOOT_OUT=${UBOOT_OUT:-$BSP_BUILD/u-boot}
APP_OUT=${APP_OUT:-$BSP_BUILD/app}
DEPLOY_OUT=${DEPLOY_OUT:-$BSP_BUILD/deploy}

JOBS=${JOBS:-$(nproc)}
# LLVM=1 uses unsuffixed clang/ld.lld; LLVM=-21 selects clang-21 and friends.
LLVM=${LLVM:-1}
# Preserve an explicit backend before Kbuild exports BINDGEN as our wrapper.
BSP_BINDGEN_BIN=${BSP_BINDGEN_BIN:-${BINDGEN:-bindgen}}
AARCH64_CC=${AARCH64_CC:-aarch64-linux-gnu-gcc}
# U-Boot is built with GCC; derive the prefix from the cross compiler.
CROSS_COMPILE=${CROSS_COMPILE:-${AARCH64_CC%gcc}}
QEMU=${QEMU:-qemu-system-aarch64}
export BSP_EXTERNAL BSP_BUILD LINUX_SRC UBOOT_SRC RKBIN_DIR LINUX_OUT \
	LINUX_MODULES_OUT LINUX_DTS_OUT UBOOT_OUT APP_OUT DEPLOY_OUT JOBS LLVM \
	AARCH64_CC CROSS_COMPILE QEMU BSP_BINDGEN_BIN UBUNTU_BASE_DIR UBUNTU_BASE_LOCAL

log() { printf '[bsp] %s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }
need_cmd() {
	local cmd
	for cmd in "$@"; do
		command -v "$cmd" >/dev/null 2>&1 || die "missing command: $cmd"
	done
}

# sha256_check FILE EXPECTED
sha256_check() {
	printf '%s  %s\n' "$2" "$1" | sha256sum --quiet -c - >/dev/null 2>&1
}

# Kbuild arguments shared by kernel, module and DTB builds.
linux_make_args() {
	printf '%s\n' -C "$LINUX_SRC" O="$LINUX_OUT" ARCH=arm64 LLVM="$LLVM" \
		BINDGEN="$BSP_ROOT/scripts/bindgen.sh"
}

linux_release() {
	local args
	mapfile -t args < <(linux_make_args)
	make -s "${args[@]}" kernelrelease
}
