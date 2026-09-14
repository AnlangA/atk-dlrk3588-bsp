#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Fetch and unpack the pinned Ubuntu Base archive as an upstream source tree.
# Local credentials and customized snapshots live outside external/.
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd curl sha256sum tar

mkdir -p "$UBUNTU_BASE_DIR"
archive=$UBUNTU_BASE_DIR/$UBUNTU_BASE_ARCHIVE
rootfs=$UBUNTU_BASE_DIR/rootfs
stamp=$UBUNTU_BASE_DIR/.rootfs.sha256
download_tmp=
extract_tmp=
cleanup() {
	[[ -z $download_tmp ]] || rm -f -- "$download_tmp"
	[[ -z $extract_tmp ]] || rm -rf -- "$extract_tmp"
}
trap cleanup EXIT

if [[ -f $archive ]] && sha256_check "$archive" "$UBUNTU_BASE_SHA256"; then
	log "Ubuntu Base archive present and verified: $archive"
else
	log "downloading Ubuntu Base $UBUNTU_BASE_VERSION $UBUNTU_BASE_ARCH"
	download_tmp=$(mktemp "$UBUNTU_BASE_DIR/.download.XXXXXXXX")
	curl -fsSL --retry 3 -o "$download_tmp" "$UBUNTU_BASE_URL/$UBUNTU_BASE_ARCHIVE"
	sha256_check "$download_tmp" "$UBUNTU_BASE_SHA256" || die "Ubuntu Base archive checksum mismatch"
	mv -- "$download_tmp" "$archive"
	download_tmp=
fi

if [[ -e $rootfs || -L $rootfs ]]; then
	[[ -d $rootfs && ! -L $rootfs && -f $stamp && $(cat "$stamp") == "$UBUNTU_BASE_SHA256" ]] ||
		die "$rootfs exists without a matching extraction stamp; move it aside or choose another UBUNTU_BASE_DIR"
	log "Ubuntu Base source tree already unpacked: $rootfs"
	exit 0
fi

extract_tmp=$(mktemp -d "$UBUNTU_BASE_DIR/.extract.XXXXXXXX")
mkdir "$extract_tmp/rootfs"
log "unpacking Ubuntu Base into $rootfs"
tar --extract --gzip --file="$archive" --directory="$extract_tmp/rootfs" --no-same-owner
mv -- "$extract_tmp/rootfs" "$rootfs"
printf '%s\n' "$UBUNTU_BASE_SHA256" > "$stamp"
log "Ubuntu Base ready: $rootfs"
