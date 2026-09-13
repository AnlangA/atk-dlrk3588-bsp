#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Write build/u-boot/u-boot-rockchip.bin (idbloader + u-boot.itb) to sector 64
# of the boot medium. Three paths are supported:
#   --board            over SSH to the eMMC of the running board (BOARD_HOST)
#   --sd /dev/sdX      to a TF card in a reader on this host
#   --maskrom          via rkdeveloptool/upgrade_tool with the board in Maskrom mode
#                      (RK_LOADER=<MiniLoaderAll.bin or rk3588_spl_loader_*.bin>,
#                       RK_FLASH_TOOL=rkdeveloptool|/path/to/upgrade_tool)
# The 32 MiB before the first GPT partition hold U-Boot; partitions are untouched.
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

image=${UBOOT_IMAGE:-$UBOOT_OUT/u-boot-rockchip.bin}
[[ -f $image ]] || die "missing $image; run make uboot"
size=$(stat -c%s "$image")
sectors=$(( (size + 511) / 512 ))
sum=$(sha256sum "$image" | cut -d' ' -f1)
(( size <= 32 * 1024 * 1024 - 64 * 512 )) || die "image does not fit before the first partition"

mode=${1:-}
case $mode in
--board)
	need_cmd ssh scp
	[[ -n ${BOARD_HOST:-} ]] || die "set BOARD_HOST=user@address"
	read -r -a ssh_opts <<< "${BOARD_SSH_OPTS:-}"
	sudo_cmd=${BOARD_SUDO:-sudo}
	dev=${BOARD_EMMC:-/dev/mmcblk0}
	model=$(ssh "${ssh_opts[@]}" "$BOARD_HOST" 'tr -d "\0" < /proc/device-tree/model')
	[[ $model == *ATK-DLRK3588* ]] || die "the target is not an ATK-DLRK3588: $model"
	log "uploading $(basename "$image") ($size bytes) to $BOARD_HOST"
	scp "${ssh_opts[@]}" -q "$image" "$BOARD_HOST:/var/tmp/u-boot-rockchip.bin"
	# shellcheck disable=SC2029
	ssh -t "${ssh_opts[@]}" "$BOARD_HOST" "set -e
		printf '%s  %s\n' '$sum' /var/tmp/u-boot-rockchip.bin | sha256sum -c -
		$sudo_cmd dd if=$dev bs=512 skip=64 count=$sectors status=none of=/var/tmp/u-boot-before.bin
		$sudo_cmd dd if=/var/tmp/u-boot-rockchip.bin of=$dev bs=512 seek=64 conv=fsync status=none
		$sudo_cmd dd if=$dev bs=512 skip=64 count=$sectors status=none | cmp - /var/tmp/u-boot-rockchip.bin
		echo 'U-Boot written to $dev sector 64 and verified; previous copy in /var/tmp/u-boot-before.bin'"
	;;
--sd)
	dev=${2:-}
	[[ -b $dev ]] || die "usage: flash-uboot.sh --sd /dev/sdX"
	need_cmd lsblk dd cmp
	tran=$(lsblk -dn -o TRAN "$dev" 2>/dev/null || true)
	[[ $tran == usb || $tran == mmc ]] || die "$dev is not a USB or MMC device (TRAN=$tran); refusing"
	sudo_cmd=; [[ $EUID -eq 0 ]] || sudo_cmd=sudo
	log "target: $(lsblk -dn -o NAME,SIZE,MODEL,TRAN "$dev")"
	read -r -p "Write $(basename "$image") to $dev sector 64? [yes/NO] " answer
	[[ $answer == yes ]] || die "aborted"
	$sudo_cmd umount "$dev"?* 2>/dev/null || true
	$sudo_cmd dd if="$image" of="$dev" bs=512 seek=64 conv=fsync status=progress
	$sudo_cmd dd if="$dev" bs=512 skip=64 count="$sectors" status=none | cmp - "$image"
	log "written and verified"
	;;
--maskrom)
	tool=${RK_FLASH_TOOL:-rkdeveloptool}
	loader=${RK_LOADER:-}
	command -v "$tool" >/dev/null || [[ -x $tool ]] || die "flash tool not found: $tool"
	[[ -f $loader ]] || die "set RK_LOADER to a Rockchip RK3588 loader (MiniLoaderAll.bin or rk3588_spl_loader_*.bin)"
	sudo_cmd=; [[ $EUID -eq 0 ]] || sudo_cmd=sudo
	log "waiting for a Rockchip USB device (VID 2207); hold UPDATE while powering on"
	for _ in $(seq 1 60); do lsusb | grep -qi ' 2207:' && break; sleep 1; done
	lsusb | grep -qi ' 2207:' || die "no Rockchip device in Maskrom mode"
	case $(basename "$tool") in
	rkdeveloptool)
		$sudo_cmd "$tool" db "$loader"
		sleep 1
		$sudo_cmd "$tool" wl 64 "$image"
		$sudo_cmd "$tool" rd
		;;
	*)
		$sudo_cmd "$tool" DB "$loader"
		sleep 1
		$sudo_cmd "$tool" WL 64 "$image"
		$sudo_cmd "$tool" RD
		;;
	esac
	log "written; remove the TF card first if eMMC was the intended target"
	;;
*)
	sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
	;;
esac
