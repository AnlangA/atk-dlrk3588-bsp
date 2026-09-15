#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Run as root from a SHA256SUMS-verified display payload.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'run as root' >&2; exit 1; }
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
case ${1:-} in
	--remove)
		systemctl disable --now slint-dashboard.service
		rm -f /etc/systemd/system/slint-dashboard.service /usr/local/bin/slint-dashboard /usr/local/libexec/slint-wait-display
		systemctl daemon-reload
		systemctl start getty@tty1.service
		echo 'Removed display service and binary; local config, user and backups retained.'
		exit 0 ;;
	''|--no-start) ;;
	*) echo 'usage: install-display.sh [--no-start|--remove]' >&2; exit 2 ;;
esac
sha256sum --quiet -c SHA256SUMS
[[ $(uname -m) == aarch64 ]] || { echo 'ARM64 target required' >&2; exit 1; }
for package in libinput10 libudev1 libxkbcommon0 libseat1 libfontconfig1 seatd fonts-dejavu-core libegl-mesa0 libgles2 libgbm1 libgl1-mesa-dri; do
	[[ $(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null) == installed ]] || {
		echo "missing package: $package; see app/slint-dashboard/README.md" >&2; exit 1;
	}
done
./slint-dashboard --metrics
getent group slint-display >/dev/null || groupadd --system slint-display
id slint-display >/dev/null 2>&1 || useradd --system --gid slint-display \
	--home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin slint-display
backup=$(mktemp -d /var/backups/slint-dashboard.XXXXXXXX)
for file in /usr/local/bin/slint-dashboard /usr/local/libexec/slint-wait-display /etc/systemd/system/slint-dashboard.service /etc/default/slint-dashboard; do
	[[ ! -e $file ]] || cp -a --parents "$file" "$backup"
done
install -m 0755 slint-dashboard /usr/local/bin/slint-dashboard.next
mv -f /usr/local/bin/slint-dashboard.next /usr/local/bin/slint-dashboard
install -m 0644 slint-dashboard.service /etc/systemd/system/slint-dashboard.service
install -D -m 0755 slint-wait-display.sh /usr/local/libexec/slint-wait-display
[[ -e /etc/default/slint-dashboard ]] || install -m 0644 slint-dashboard.default /etc/default/slint-dashboard
systemd-analyze verify /etc/systemd/system/slint-dashboard.service
systemctl daemon-reload
systemctl enable seatd.service slint-dashboard.service
if [[ ${1:-} != --no-start ]]; then
	systemctl start seatd.service
	systemctl restart --no-block slint-dashboard.service
fi
echo "Installed Slint display; backup: $backup"
