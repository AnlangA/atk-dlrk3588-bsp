#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the mainline kernel with the board patches, then the out-of-tree Rust
# modules and the board device tree against that build.
# Usage: build-linux.sh [kernel make targets]   (default: Image modules)
#   BSP_RECONFIGURE=1  regenerate .config from defconfig and linux/configs/*.config
#   CLIPPY=1           run kernel Clippy instead of a plain rustc build
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd make rustc bindgen

"$BSP_ROOT/scripts/prepare.sh" linux
mapfile -t args < <(linux_make_args)
[[ -n ${CLIPPY:-} ]] && args+=(CLIPPY="$CLIPPY")
export KBUILD_BUILD_USER=${KBUILD_BUILD_USER:-bsp}
export KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-atk-dlrk3588}
mkdir -p "$LINUX_OUT"

log "checking the Rust toolchain against $LINUX_SRC"
make "${args[@]}" rustavailable

if [[ ! -f $LINUX_OUT/.config || -n ${BSP_RECONFIGURE:-} ]]; then
	log "configuring: arm64 defconfig + linux/configs/*.config"
	make "${args[@]}" defconfig
	"$LINUX_SRC/scripts/kconfig/merge_config.sh" -m -O "$LINUX_OUT" \
		"$LINUX_OUT/.config" "$BSP_ROOT"/linux/configs/*.config
	make "${args[@]}" olddefconfig
fi
for symbol in RUST MODULES SERIAL_CORE DMA_ENGINE PL330_DMA DEBUG_FS ARCH_ROCKCHIP COMMON_CLK; do
	value=$("$LINUX_SRC/scripts/config" --file "$LINUX_OUT/.config" -s "$symbol")
	[[ $value == y ]] || die "CONFIG_$symbol=$value; the Rust UART modules need it built in"
done

targets=("$@")
[[ ${#targets[@]} -gt 0 ]] || targets=(Image modules)
log "building kernel: ${targets[*]}"
make "${args[@]}" -j"$JOBS" "${targets[@]}"

log "building out-of-tree modules from linux/drivers"
make "${args[@]}" -j"$JOBS" M="$BSP_ROOT/linux/drivers" MO="$LINUX_MODULES_OUT" modules

log "building device tree from linux/dts"
make "${args[@]}" M="$BSP_ROOT/linux/dts" MO="$LINUX_DTS_OUT"

release=$(linux_release)
log "kernel release: $release"
log "Image:   $LINUX_OUT/arch/arm64/boot/Image"
log "DTB:     $LINUX_DTS_OUT/rk3588-atk-dlrk3588.dtb"
log "modules: $LINUX_MODULES_OUT/*.ko"
