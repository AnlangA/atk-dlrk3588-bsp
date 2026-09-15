#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Usage: deploy-display.sh [--no-start|--remove]
# BOARD_SUDO and BOARD_SSH_OPTS have the same meaning as deploy-board.sh.
# BOARD_SUDO_PASSWORD_FILE optionally supplies one password line on SSH stdin.
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd ssh scp sha256sum
[[ -n ${BOARD_HOST:-} ]] || die "set BOARD_HOST in local.env"
case ${1:-} in ''|--no-start|--remove) ;; *) die "unknown argument: $1" ;; esac
read -r -a ssh_opts <<< "${BOARD_SSH_OPTS:-}"
payload=$BSP_BUILD/display-deploy
mkdir -p "$payload"
install -m 0755 "${DISPLAY_OUT:-$BSP_BUILD/slint}/aarch64-unknown-linux-gnu/release/slint-dashboard" "$payload/slint-dashboard"
install -m 0755 "$BSP_ROOT/board/install-display.sh" "$payload/install-display.sh"
install -m 0755 "$BSP_ROOT/board/slint-wait-display.sh" "$payload/slint-wait-display.sh"
install -m 0644 "$BSP_ROOT/board/slint-dashboard.service" "$BSP_ROOT/board/slint-dashboard.default" "$payload/"
(cd "$payload" && sha256sum slint-dashboard install-display.sh slint-wait-display.sh slint-dashboard.service slint-dashboard.default > SHA256SUMS)
remote=$(ssh "${ssh_opts[@]}" "$BOARD_HOST" 'mktemp -d /var/tmp/slint-deploy.XXXXXXXX')
[[ $remote =~ ^/var/tmp/slint-deploy\.[a-zA-Z0-9]+$ ]] || die "unexpected upload directory"
scp "${ssh_opts[@]}" -q "$payload/"* "$BOARD_HOST:$remote/"
sudo_cmd=${BOARD_SUDO:-sudo}
if [[ -n ${BOARD_SUDO_PASSWORD_FILE:-} ]]; then
	# Pass the secret on stdin, never in argv, the payload or logs.
	# shellcheck disable=SC2029
	ssh "${ssh_opts[@]}" "$BOARD_HOST" "$sudo_cmd -S -p '' bash '$remote/install-display.sh' ${1:-}" < "$BOARD_SUDO_PASSWORD_FILE"
else
	# shellcheck disable=SC2029
	ssh "${ssh_opts[@]}" "$BOARD_HOST" "$sudo_cmd bash '$remote/install-display.sh' ${1:-}"
fi
# shellcheck disable=SC2029
ssh "${ssh_opts[@]}" "$BOARD_HOST" "rm -rf -- '$remote'"
log "Slint service installed; see journalctl -u slint-dashboard.service"
