#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Fetch the pinned upstream sources listed in manifest.env into external/.
# Usage: fetch.sh [linux|u-boot|rkbin|ubuntu-base]...   (default: all)
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd git curl sha256sum

# clone_at_tag DIR URL TAG COMMIT
clone_at_tag() {
	local dir=$1 url=$2 tag=$3 commit=$4 head
	if [[ -e $dir/.git ]]; then
		if git -C "$dir" merge-base --is-ancestor "$commit" HEAD 2>/dev/null; then
			log "$dir already contains $tag ($commit)"
			return 0
		fi
		die "$dir exists but does not contain $tag; remove it or point the *_SRC variable elsewhere"
	fi
	log "cloning $url at $tag into $dir"
	git -c advice.detachedHead=false clone --depth 1 --branch "$tag" "$url" "$dir"
	head=$(git -C "$dir" rev-parse HEAD)
	[[ $head == "$commit" ]] || die "$tag resolved to $head, expected $commit"
}

# fetch_blob RELATIVE_PATH SHA256
fetch_blob() {
	local rel=$1 sha=$2 dest=$RKBIN_DIR/$1
	if [[ -f $dest ]] && sha256_check "$dest" "$sha"; then
		log "rkbin/$rel present"
		return 0
	fi
	mkdir -p "$(dirname -- "$dest")"
	log "downloading rkbin/$rel at $RKBIN_COMMIT"
	curl -fsSL -o "$dest.tmp" "$RKBIN_RAW_URL/$RKBIN_COMMIT/$rel"
	sha256_check "$dest.tmp" "$sha" || { rm -f "$dest.tmp"; die "checksum mismatch for $rel"; }
	mv "$dest.tmp" "$dest"
}

targets=("$@")
[[ ${#targets[@]} -gt 0 ]] || targets=(linux u-boot rkbin ubuntu-base)
mkdir -p "$BSP_EXTERNAL"
for target in "${targets[@]}"; do
	case $target in
	linux) clone_at_tag "$LINUX_SRC" "$LINUX_URL" "$LINUX_TAG" "$LINUX_COMMIT" ;;
	u-boot) clone_at_tag "$UBOOT_SRC" "$UBOOT_URL" "$UBOOT_TAG" "$UBOOT_COMMIT" ;;
	ubuntu-base) "$BSP_ROOT/scripts/fetch-ubuntu-base.sh" ;;
	rkbin)
		fetch_blob "$RKBIN_BL31" "$RKBIN_BL31_SHA256"
		fetch_blob "$RKBIN_DDR" "$RKBIN_DDR_SHA256"
		fetch_blob "$RKBIN_DDRBIN_TOOL" "$RKBIN_DDRBIN_TOOL_SHA256"
		chmod +x "$RKBIN_DIR/$RKBIN_DDRBIN_TOOL"
		;;
	*) die "unknown fetch target: $target" ;;
	esac
done
