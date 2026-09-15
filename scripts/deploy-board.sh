#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copy the packaged payload to a running Ubuntu board over SSH and run
# board/install.sh there. The board keeps its previous kernels and boot
# entries; the new entry becomes the default unless --no-default is given.
# Usage: deploy-board.sh [--reboot] [--no-default] [--boot-dir NAME] [--label LABEL]
#   BOARD_HOST      user@address of the board (required, e.g. ubuntu@10.42.0.88)
#   BOARD_SSH_OPTS  extra ssh/scp options, e.g. "-i ~/.ssh/board -o StrictHostKeyChecking=yes"
#   BOARD_SUDO      command prefix for root on the board (default: sudo)
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd ssh scp

[[ -n ${BOARD_HOST:-} ]] || die "set BOARD_HOST=user@address (for example in local.env)"
read -r -a ssh_opts <<< "${BOARD_SSH_OPTS:-}"
sudo_cmd=${BOARD_SUDO:-sudo}

release=$(cat "$DEPLOY_OUT/payload/KERNEL_RELEASE" 2>/dev/null) ||
	die "no packaged payload; run make package first"
tarball=$DEPLOY_OUT/atk-dlrk3588-bsp-$release.tar.gz
[[ -f $tarball ]] || die "missing $tarball; run make package"
sum=$(sha256sum "$tarball" | cut -d' ' -f1)
remote_dir=/var/tmp/atk-dlrk3588-bsp

log "checking $BOARD_HOST"
model=$(ssh "${ssh_opts[@]}" "$BOARD_HOST" 'tr -d "\0" < /proc/device-tree/model; echo; uname -r')
log "board: $(printf '%s' "$model" | tr '\n' ' ')"
[[ $model == *ATK-DLRK3588* ]] || die "the target is not an ATK-DLRK3588"

log "uploading $(basename "$tarball")"
# shellcheck disable=SC2029  # remote paths and the checksum are meant to expand here
ssh "${ssh_opts[@]}" "$BOARD_HOST" "mkdir -p $remote_dir"
scp "${ssh_opts[@]}" -q "$tarball" "$BOARD_HOST:$remote_dir/payload.tar.gz"
# shellcheck disable=SC2029
ssh "${ssh_opts[@]}" "$BOARD_HOST" "printf '%s  %s\n' '$sum' $remote_dir/payload.tar.gz | sha256sum -c - &&
	rm -rf $remote_dir/payload && tar -xzf $remote_dir/payload.tar.gz -C $remote_dir"

log "installing on the board"
install_args=
if (( $# )); then printf -v install_args ' %q' "$@"; fi
if [[ -n ${BOARD_SUDO_PASSWORD_FILE:-} ]]; then
	# shellcheck disable=SC2029  # arguments are shell-escaped above
	ssh "${ssh_opts[@]}" "$BOARD_HOST" "$sudo_cmd -S -p '' $remote_dir/payload/install.sh$install_args" < "$BOARD_SUDO_PASSWORD_FILE"
else
	# shellcheck disable=SC2029  # arguments are shell-escaped above
	ssh -t "${ssh_opts[@]}" "$BOARD_HOST" "$sudo_cmd $remote_dir/payload/install.sh$install_args"
fi
log "done; after a reboot run: $sudo_cmd $remote_dir/payload/board-smoke.sh $release"
