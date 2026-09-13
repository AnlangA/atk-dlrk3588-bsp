#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Export the prepared source tree back into this repository: overlay files
# are copied from the tree, and every other change on top of the pinned tag
# is regenerated as <component>/patches/*.patch. Develop with ordinary git
# commits in the tree, then run this before committing here.
# Usage: export-patches.sh <linux|u-boot>
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd git

component=${1:-}
case $component in
linux) src=$LINUX_SRC base=$LINUX_COMMIT ;;
u-boot) src=$UBOOT_SRC base=$UBOOT_COMMIT ;;
*) die "usage: export-patches.sh <linux|u-boot>" ;;
esac
patch_dir=$BSP_ROOT/$component/patches
overlay_dir=$BSP_ROOT/$component/overlay
stamp=$BSP_BUILD/$component-patches.stamp

[[ -e $src/.git ]] || die "$src is not a git checkout"
[[ -z $(git -C "$src" status --porcelain --untracked-files=no) ]] ||
	die "$src has uncommitted changes; commit them first"
git -C "$src" merge-base --is-ancestor "$base" HEAD ||
	die "HEAD of $src does not descend from $base"

mapfile -t overlay_files < <(cd "$overlay_dir" 2>/dev/null && find . -type f -printf '%P\n' | sort)
exclude=()
for f in "${overlay_files[@]}"; do
	[[ -f $src/$f ]] || die "overlay file $f is missing from $src"
	install -D -m "$(stat -c %a "$src/$f")" "$src/$f" "$overlay_dir/$f"
	exclude+=(":(exclude)$f")
done

rm -f "$patch_dir"/*.patch
mkdir -p "$patch_dir"
git -C "$src" format-patch --no-signature --zero-commit --full-index -o "$patch_dir" "$base..HEAD" -- . "${exclude[@]}" >/dev/null
shopt -s nullglob
patches=("$patch_dir"/*.patch)
shopt -u nullglob
series=$( { cat "${patches[@]}" /dev/null; for f in "${overlay_files[@]}"; do printf '%s\n' "$f"; cat "$overlay_dir/$f"; done; } | sha256sum | cut -d' ' -f1)
mkdir -p "$BSP_BUILD"
printf 'STAMP_SERIES=%s\nSTAMP_HEAD=%s\n' "$series" "$(git -C "$src" rev-parse HEAD)" > "$stamp"
log "$component: ${#overlay_files[@]} overlay files refreshed, ${#patches[@]} patches written to $patch_dir"
ls -1 "$patch_dir"
log "new files created in the tree end up in patches; move them to $overlay_dir to keep them as plain files"
