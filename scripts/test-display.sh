#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Run the GPU/scanout validation on the board; --touch injects UI touch events.
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd ssh scp
[[ -n ${BOARD_HOST:-} ]] || die "set BOARD_HOST in local.env"
case ${1:-} in ''|--touch) ;; *) die "usage: test-display.sh [--touch]" ;; esac
read -r -a ssh_opts <<< "${BOARD_SSH_OPTS:-}"
remote=$(ssh "${ssh_opts[@]}" "$BOARD_HOST" 'mktemp -d /var/tmp/slint-test.XXXXXXXX')
[[ $remote =~ ^/var/tmp/slint-test\.[a-zA-Z0-9]+$ ]] || die "unexpected test directory"
cleanup() {
	# shellcheck disable=SC2029
	ssh "${ssh_opts[@]}" "$BOARD_HOST" "rm -rf -- '$remote'"
}
trap cleanup EXIT
scp "${ssh_opts[@]}" -q "$BSP_ROOT/board/test-display-gpu.py" "$BOARD_HOST:$remote/test.py"
sudo_cmd=${BOARD_SUDO:-sudo}
if [[ -n ${BOARD_SUDO_PASSWORD_FILE:-} ]]; then
	# shellcheck disable=SC2029
	ssh "${ssh_opts[@]}" "$BOARD_HOST" "$sudo_cmd -S -p '' python3 '$remote/test.py' ${1:-}" < "$BOARD_SUDO_PASSWORD_FILE"
else
	# shellcheck disable=SC2029
	ssh "${ssh_opts[@]}" "$BOARD_HOST" "$sudo_cmd python3 '$remote/test.py' ${1:-}"
fi
