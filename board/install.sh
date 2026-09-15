#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runs as root on the ATK-DLRK3588 from an extracted payload directory created
# by scripts/package.sh. Installs the kernel, DTB, modules, application and
# board services, adds an extlinux boot entry and keeps the previous entries.
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: install.sh [--boot-dir NAME] [--label LABEL] [--title TEXT]
                  [--no-default] [--reboot]
  --boot-dir NAME  directory under /boot for Image and DTB (default: atk-dlrk3588-bsp)
  --label LABEL    extlinux label (default: bsp)
  --title TEXT     menu title
  --no-default     add the entry without making it the default
  --reboot         reboot after a successful installation
EOF
}

boot_dir=atk-dlrk3588-bsp
label=bsp
title=
make_default=1
reboot_after=0
while [[ $# -gt 0 ]]; do
	case $1 in
	--boot-dir) boot_dir=$2; shift 2 ;;
	--label) label=$2; shift 2 ;;
	--title) title=$2; shift 2 ;;
	--no-default) make_default=0; shift ;;
	--reboot) reboot_after=1; shift ;;
	-h|--help) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
	esac
done
[[ $boot_dir =~ ^[A-Za-z0-9._-]+$ && $label =~ ^[A-Za-z0-9._-]+$ ]] || {
	echo 'Boot directory and label must be plain names.' >&2; exit 2;
}

payload=$(cd -- "$(dirname -- "$0")" && pwd)
[[ $EUID -eq 0 ]] || { echo 'Run as root on the development board.' >&2; exit 1; }
model=$(tr -d '\0' < /proc/device-tree/model)
[[ $model == *ATK-DLRK3588* ]] || { echo "Unexpected board: $model" >&2; exit 1; }
mountpoint -q /boot || { echo '/boot is not a mounted boot partition.' >&2; exit 1; }
(cd "$payload" && sha256sum --quiet -c SHA256SUMS)
release=$(cat "$payload/KERNEL_RELEASE")
[[ -n $release && -d $payload/lib/modules/$release ]] || {
	echo 'Payload lacks modules for its kernel release.' >&2; exit 1;
}
title=${title:-"Ubuntu - ATK-DLRK3588 BSP Linux ${release}"}
if [[ -e /dev/ttyRU0 ]] && command -v fuser >/dev/null && fuser -s /dev/ttyRU0; then
	echo '/dev/ttyRU0 is in use; close its applications first.' >&2; exit 1
fi

target=/boot/$boot_dir
need=$(du -sbc "$payload/boot/Image" "$payload/boot/rk3588-atk-dlrk3588.dtb" | tail -1 | cut -f1)
replace_image=1
if cmp -s "$payload/boot/Image" "$target/Image"; then
	replace_image=0
	need=$((need - $(stat -c %s "$payload/boot/Image")))
fi
free=$(df --output=avail -B1 /boot | tail -1)
# Image.new must coexist with the previous Image until verification succeeds.
# Counting the old image as free space would defeat this atomic replacement.
if (( free < need + 4194304 )); then
	echo "Not enough space in /boot for $target (need $need bytes, $free available)." >&2
	echo 'Existing kernel directories:' >&2
	find /boot -mindepth 1 -maxdepth 1 -type d ! -name extlinux ! -name lost+found -exec du -sh {} + >&2 || true
	echo 'Back up and retire an unused boot entry first; Image.new needs temporary space.' >&2
	exit 1
fi

stamp=$(date +%Y%m%d-%H%M%S)
backup=/var/backups/atk-dlrk3588-bsp/$stamp
mkdir -p "$backup"
uname -a > "$backup/kernel-before.txt"
if [[ -d /boot/extlinux ]]; then
	saved=(extlinux)
	[[ -d $target ]] && saved+=("$boot_dir")
	tar -C /boot -czf "$backup/boot-before.tar.gz" "${saved[@]}"
fi
for path in /usr/local/bin/rs485-test /usr/local/sbin/bind-uart3.sh \
	/etc/systemd/system/rust-uart3.service /etc/udev/rules.d/70-rust-uart.rules; do
	[[ -e $path ]] && cp -a "$path" "$backup/"
done
if [[ -d /lib/modules/$release ]]; then
	mv "/lib/modules/$release" "$backup/modules-$release"
fi
sync

restore() {
	echo 'Installation failed; restoring the previous boot configuration.' >&2
	if [[ -f $backup/boot-before.tar.gz ]]; then
		tar -C /boot -xzf "$backup/boot-before.tar.gz"
	fi
	if [[ -d $backup/modules-$release ]]; then
		rm -rf "/lib/modules/$release"
		mv "$backup/modules-$release" "/lib/modules/$release"
	fi
	sync
}
trap restore ERR

cp -a "$payload/lib/modules/$release" /lib/modules/
depmod -a "$release"
install -D -m 0755 "$payload/usr/local/bin/rs485-test" /usr/local/bin/rs485-test
install -D -m 0755 "$payload/usr/local/sbin/bind-uart3.sh" /usr/local/sbin/bind-uart3.sh
install -D -m 0644 "$payload/etc/udev/rules.d/70-rust-uart.rules" /etc/udev/rules.d/70-rust-uart.rules
install -D -m 0644 "$payload/etc/systemd/system/rust-uart3.service" /etc/systemd/system/rust-uart3.service
udevadm control --reload-rules || true
systemctl daemon-reload
systemctl enable rust-uart3.service
command -v fuser >/dev/null || echo 'Warning: bind-uart3.sh needs fuser; install the psmisc package.' >&2

mkdir -p "$target"
if (( replace_image )); then
	install -m 0644 "$payload/boot/Image" "$target/Image.new"
	cmp "$payload/boot/Image" "$target/Image.new"
	mv "$target/Image.new" "$target/Image"
fi
install -m 0644 "$payload/boot/rk3588-atk-dlrk3588.dtb" "$target/rk3588-atk-dlrk3588.dtb.new"
mv "$target/rk3588-atk-dlrk3588.dtb.new" "$target/rk3588-atk-dlrk3588.dtb"

conf=/boot/extlinux/extlinux.conf
mkdir -p /boot/extlinux
if [[ -f $conf ]]; then
	default=$(awk 'toupper($1)=="DEFAULT"{print $2; exit}' "$conf")
	timeout=$(awk 'toupper($1)=="TIMEOUT"{print $2; exit}' "$conf")
	append=$(awk -v want="$default" '
		toupper($1)=="LABEL"{cur=$2}
		toupper($1)=="APPEND" && (want=="" || cur==want){
			sub(/^[ \t]*[Aa][Pp][Pp][Ee][Nn][Dd][ \t]+/, ""); print; exit}' "$conf")
	[[ -n $append ]] || { echo "No APPEND line found in $conf" >&2; false; }
	others=$(awk -v skip="$label" '
		toupper($1)=="DEFAULT" || toupper($1)=="TIMEOUT" {next}
		toupper($1)=="LABEL" {cur=$2}
		cur==skip {next}
		{print}' "$conf")
	if (( make_default )); then new_default=$label; else new_default=${default:-$label}; fi
	{
		printf 'DEFAULT %s\nTIMEOUT %s\n\n' "$new_default" "${timeout:-30}"
		printf 'LABEL %s\n    MENU LABEL %s\n    LINUX /%s/Image\n    FDT /%s/rk3588-atk-dlrk3588.dtb\n    APPEND %s\n\n' \
			"$label" "$title" "$boot_dir" "$boot_dir" "$append"
		printf '%s\n' "$others" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
	} > "$conf.new"
else
	sed -e "s|@LABEL@|$label|g" -e "s|@TITLE@|$title|g" -e "s|@DIR@|$boot_dir|g" \
		-e '/^#/d' "$payload/boot/extlinux.conf.in" > "$conf.new"
fi
mv "$conf.new" "$conf"
sync
trap - ERR

printf '%s\n' "$backup" > /var/backups/atk-dlrk3588-bsp/latest
echo "Installed Linux $release into $target; backup in $backup"
cat "$conf"
sha256sum "$target/Image" "$target/rk3588-atk-dlrk3588.dtb"
modinfo -F vermagic "/lib/modules/$release/extra/rust_dw_uart.ko" 2>/dev/null ||
	modinfo -F vermagic "/lib/modules/$release/updates/rust_dw_uart.ko" 2>/dev/null || true
echo ATK_DLRK3588_BSP_INSTALLED
if (( reboot_after )); then
	systemctl reboot
fi
