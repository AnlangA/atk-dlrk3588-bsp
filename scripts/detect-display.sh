#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Read the panel resistor on the board. --dtb selects the supported J23 DTB.
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd ssh python3
[[ -n ${BOARD_HOST:-} ]] || die "set BOARD_HOST in local.env"
case ${1:-} in ''|--dtb) ;; *) die "usage: detect-display.sh [--dtb]" ;; esac
read -r -a ssh_opts <<< "${BOARD_SSH_OPTS:-}"
result=$(ssh "${ssh_opts[@]}" "$BOARD_HOST" python3 - < "$BSP_ROOT/board/detect-mipi-panel.py")
if [[ ${1:-} == --dtb ]]; then
	python3 -c 'import json, sys
panel = json.load(sys.stdin)
if panel["profile"] != "5p5-1080x1920":
    sys.exit("Identified " + panel["profile"] + "; this BSP currently implements only the J23 1080p panel")
print("rk3588-atk-dlrk3588-mipi-1080p.dtb")' <<< "$result"
else
	printf '%s\n' "$result"
fi
