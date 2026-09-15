#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Install Ubuntu runtime dependencies for Mali/Panthor Slint rendering.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'run as root' >&2; exit 1; }
model=$(tr -d '\0' < /proc/device-tree/model)
[[ $model == *ATK-DLRK3588* ]] || { echo "unexpected board: $model" >&2; exit 1; }
apt-get install -y --no-install-recommends \
	libinput10 libudev1 libxkbcommon0 libseat1 seatd fonts-dejavu-core \
	libfontconfig1 xkb-data libegl-mesa0 libgles2 libgbm1 libgl1-mesa-dri \
	linux-firmware-misc zstd

# Ubuntu ships compressed firmware. This BSP's existing kernel was built
# without FW_LOADER_COMPRESS, so provide the same signed-package payload in
# uncompressed form. Re-run after updating linux-firmware-misc to refresh it.
firmware=/lib/firmware/arm/mali/arch10.8/mali_csffw.bin
if [[ -f $firmware.zst ]]; then
	zstd -q -d -c < "$firmware.zst" > "$firmware.new"
	chmod 0644 "$firmware.new"
	mv "$firmware.new" "$firmware"
fi
[[ -s $firmware ]] || { echo "missing Panthor firmware: $firmware" >&2; exit 1; }
sha256sum "$firmware"
