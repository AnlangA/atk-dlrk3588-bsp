#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Install only the rs485-test application on a running board over SSH. The
# kernel, modules and services stay untouched, so no reboot is needed.
# Usage: deploy-app.sh [--check]
#   --check         run "rs485-test chardev" on the board afterwards
#   BOARD_HOST      user@address of the board (required)
#   BOARD_SSH_OPTS  extra ssh/scp options
#   BOARD_SUDO      command prefix for root on the board (default: sudo)
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd ssh scp sha256sum

[[ -n ${BOARD_HOST:-} ]] || die "set BOARD_HOST=user@address (for example in local.env)"
read -r -a ssh_opts <<< "${BOARD_SSH_OPTS:-}"
sudo_cmd=${BOARD_SUDO:-sudo}
check=0
[[ ${1:-} == --check ]] && check=1

app=$APP_OUT/aarch64-unknown-linux-gnu/release/rs485-test
[[ -f $app ]] || die "missing $app; run make app first"
sum=$(sha256sum "$app" | cut -d' ' -f1)

log "uploading rs485-test ($sum) to $BOARD_HOST"
scp "${ssh_opts[@]}" -q "$app" "$BOARD_HOST:/tmp/rs485-test.new"
# shellcheck disable=SC2029  # the checksum is meant to expand on the client side
ssh "${ssh_opts[@]}" "$BOARD_HOST" "set -e
	printf '%s  %s\n' '$sum' /tmp/rs485-test.new | sha256sum -c -
	$sudo_cmd install -m 0755 /tmp/rs485-test.new /usr/local/bin/rs485-test.next
	$sudo_cmd mv /usr/local/bin/rs485-test.next /usr/local/bin/rs485-test
	rm -f /tmp/rs485-test.new
	sha256sum /usr/local/bin/rs485-test"
if (( check )); then
	log "running the character-device test on the board"
	ssh "${ssh_opts[@]}" "$BOARD_HOST" "/usr/local/bin/rs485-test chardev --device /dev/rust-chardev"
fi
log "rs485-test installed"
