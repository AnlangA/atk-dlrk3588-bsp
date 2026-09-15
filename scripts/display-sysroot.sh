#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# The board needs libc6-dev, libinput-dev, libudev-dev, libxkbcommon-dev,
# libseat-dev and libfontconfig-dev. This target only reads the board.
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd ssh rsync python3
: "${BOARD_HOST:?set BOARD_HOST in local.env}"
sysroot=${DISPLAY_SYSROOT:-$BSP_BUILD/slint-sysroot}
read -r -a ssh_opts <<< "${BOARD_SSH_OPTS:-}"
ssh "${ssh_opts[@]}" "$BOARD_HOST" \
	'pkg-config --exists libinput libudev xkbcommon libseat fontconfig gbm egl glesv2' ||
	die "install the documented board development packages first"
mkdir -p "$sysroot/usr/lib" "$sysroot/usr/include" "$sysroot/usr/share"
for path in usr/lib/aarch64-linux-gnu usr/include usr/share/pkgconfig; do
	rsync -a -e "ssh ${BOARD_SSH_OPTS:-}" "$BOARD_HOST:/$path/" "$sysroot/$path/"
done
rsync -a -e "ssh ${BOARD_SSH_OPTS:-}" "$BOARD_HOST:/usr/lib/ld-linux-aarch64.so.1" "$sysroot/usr/lib/"
# Ubuntu uses merged /usr. Keep absolute symlinks inside the copied sysroot.
ln -sfn usr/lib "$sysroot/lib"
python3 - "$sysroot" <<'PY'
import os
from pathlib import Path
import sys
root = Path(sys.argv[1]).resolve()
for base, directories, files in os.walk(root / "usr"):
    for name in directories + files:
        path = Path(base) / name
        if path.is_symlink():
            target = os.readlink(path)
            if target.startswith("/"):
                path.unlink()
                path.symlink_to(os.path.relpath(root / target.lstrip("/"), path.parent))
PY
ssh "${ssh_opts[@]}" "$BOARD_HOST" 'dpkg-query -W' > "$sysroot/packages.tsv"
log "target sysroot: $sysroot"
