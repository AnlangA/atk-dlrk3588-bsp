#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build mainline U-Boot with the ATK-DLRK3588 board patches. The DDR init
# blob is derived from the pinned rkbin release with the board parameters in
# u-boot/ddrbin_param.txt; BL31 is used as released.
# Usage: build-uboot.sh [u-boot make targets]
#   BL31=..., ROCKCHIP_TPL=...  override the firmware blobs
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd make "${CROSS_COMPILE}gcc" python3

"$BSP_ROOT/scripts/prepare.sh" u-boot
mkdir -p "$UBOOT_OUT"

if [[ -z ${BL31:-} || -z ${ROCKCHIP_TPL:-} ]]; then
	"$BSP_ROOT/scripts/fetch.sh" rkbin
fi
BL31=${BL31:-$RKBIN_DIR/$RKBIN_BL31}
if [[ -z ${ROCKCHIP_TPL:-} ]]; then
	ROCKCHIP_TPL=$UBOOT_OUT/rk3588_ddr_atk-dlrk3588.bin
	if ! { [[ -f $ROCKCHIP_TPL ]] && sha256_check "$ROCKCHIP_TPL" "$BOARD_DDR_SHA256"; }; then
		log "deriving the board DDR blob from rkbin $(basename "$RKBIN_DDR")"
		cp "$RKBIN_DIR/$RKBIN_DDR" "$ROCKCHIP_TPL.tmp"
		"$RKBIN_DIR/$RKBIN_DDRBIN_TOOL" rk3588 "$BSP_ROOT/u-boot/ddrbin_param.txt" \
			"$ROCKCHIP_TPL.tmp" | grep -E '^(lp4|lp4x)_freq|modify end' || true
		sha256_check "$ROCKCHIP_TPL.tmp" "$BOARD_DDR_SHA256" || {
			rm -f "$ROCKCHIP_TPL.tmp"
			die "derived DDR blob does not match BOARD_DDR_SHA256; update manifest.env if ddrbin_param.txt changed on purpose"
		}
		mv "$ROCKCHIP_TPL.tmp" "$ROCKCHIP_TPL"
	fi
fi
[[ -f $BL31 ]] || die "BL31 not found: $BL31"
[[ -f $ROCKCHIP_TPL ]] || die "ROCKCHIP_TPL not found: $ROCKCHIP_TPL"
export BL31 ROCKCHIP_TPL

args=(-C "$UBOOT_SRC" O="$UBOOT_OUT" CROSS_COMPILE="$CROSS_COMPILE")
if [[ ! -f $UBOOT_OUT/.config ]]; then
	make "${args[@]}" atk-dlrk3588_defconfig
fi
targets=("$@")
make "${args[@]}" -j"$JOBS" "${targets[@]}"

log "U-Boot image: $UBOOT_OUT/u-boot-rockchip.bin (write to sector 64 of eMMC or SD)"
log "BL31: $BL31"
log "TPL:  $ROCKCHIP_TPL"
