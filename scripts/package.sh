#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Assemble the board payload (kernel, DTB, modules, application, board files
# and the on-board installer) into build/deploy/ and a checksummed tarball.
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd make tar sha256sum

image=$LINUX_OUT/arch/arm64/boot/Image
dtb=$LINUX_DTS_OUT/rk3588-atk-dlrk3588.dtb
app=$APP_OUT/aarch64-unknown-linux-gnu/release/rs485-test
for file in "$image" "$dtb" "$app" "$LINUX_MODULES_OUT/rust_dw_uart.ko" "$LINUX_MODULES_OUT/rust_chardev.ko"; do
	[[ -f $file ]] || die "missing $file; run make linux app first"
done
release=$(linux_release)
mapfile -t args < <(linux_make_args)

stage=$DEPLOY_OUT/payload
rm -rf "$stage"
mkdir -p "$stage/boot" "$stage/usr/local/bin" "$stage/usr/local/sbin" \
	"$stage/etc/systemd/system" "$stage/etc/udev/rules.d"

log "installing modules for $release"
make "${args[@]}" -s INSTALL_MOD_PATH="$stage" INSTALL_MOD_STRIP=1 modules_install
make "${args[@]}" -s M="$BSP_ROOT/linux/drivers" MO="$LINUX_MODULES_OUT" \
	INSTALL_MOD_PATH="$stage" INSTALL_MOD_STRIP=1 modules_install
rm -f "$stage/lib/modules/$release/build" "$stage/lib/modules/$release/source"
if command -v depmod >/dev/null; then
	depmod -b "$stage" "$release"
fi
[[ -d $stage/lib/modules/$release ]] || die "modules_install did not produce lib/modules/$release"

install -m 0644 "$image" "$stage/boot/Image"
install -m 0644 "$dtb" "$stage/boot/rk3588-atk-dlrk3588.dtb"
install -m 0644 "$BSP_ROOT/board/extlinux.conf.in" "$stage/boot/extlinux.conf.in"
install -m 0755 "$app" "$stage/usr/local/bin/rs485-test"
install -m 0755 "$BSP_ROOT/board/bind-uart3.sh" "$stage/usr/local/sbin/bind-uart3.sh"
install -m 0644 "$BSP_ROOT/board/rust-uart3.service" "$stage/etc/systemd/system/rust-uart3.service"
install -m 0644 "$BSP_ROOT/board/70-rust-uart.rules" "$stage/etc/udev/rules.d/70-rust-uart.rules"
install -m 0755 "$BSP_ROOT/board/install.sh" "$stage/install.sh"
install -m 0755 "$BSP_ROOT/tests/board-smoke.sh" "$stage/board-smoke.sh"
printf '%s\n' "$release" > "$stage/KERNEL_RELEASE"
(cd "$stage" && find . -type f -print0 | sort -z | xargs -0 sha256sum > ../SHA256SUMS.tmp)
mv "$DEPLOY_OUT/SHA256SUMS.tmp" "$stage/SHA256SUMS"

tarball=$DEPLOY_OUT/atk-dlrk3588-bsp-$release.tar.gz
tar -C "$DEPLOY_OUT" -czf "$tarball" payload
artifacts=("$(basename "$tarball")")
if [[ -f $UBOOT_OUT/u-boot-rockchip.bin ]]; then
	install -m 0644 "$UBOOT_OUT/u-boot-rockchip.bin" "$DEPLOY_OUT/u-boot-rockchip.bin"
	artifacts+=(u-boot-rockchip.bin)
fi
(cd "$DEPLOY_OUT" && sha256sum "${artifacts[@]}" > SHA256SUMS)
log "payload: $tarball"
cat "$DEPLOY_OUT/SHA256SUMS"
log "payload size: $(du -sh "$stage" | cut -f1)"
