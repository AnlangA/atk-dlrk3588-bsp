#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Turn the pristine upstream checkout into the board tree:
#   1. git am <component>/patches/*.patch   (edits to existing upstream files)
#   2. copy <component>/overlay/ over the tree and commit it (new files only)
# Re-running is a no-op while patches, overlay and tree match; a changed
# series is re-applied from the pinned tag when the tree has no local edits.
# Usage: prepare.sh <linux|u-boot>
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd git

component=${1:-}
case $component in
linux) src=$LINUX_SRC tag=$LINUX_TAG base=$LINUX_COMMIT ;;
u-boot) src=$UBOOT_SRC tag=$UBOOT_TAG base=$UBOOT_COMMIT ;;
*) die "usage: prepare.sh <linux|u-boot>" ;;
esac
patch_dir=$BSP_ROOT/$component/patches
overlay_dir=$BSP_ROOT/$component/overlay
branch=atk-dlrk3588-bsp
stamp=$BSP_BUILD/$component-patches.stamp
git_id=(-c user.name=atk-dlrk3588-bsp -c user.email=bsp@localhost -c advice.detachedHead=false)

[[ -e $src/.git ]] || die "$src is not a git checkout; run scripts/fetch.sh $component"
shopt -s nullglob
patches=("$patch_dir"/*.patch)
shopt -u nullglob
mapfile -t overlay_files < <(cd "$overlay_dir" 2>/dev/null && find . -type f -printf '%P\n' | sort)
[[ ${#patches[@]} -gt 0 || ${#overlay_files[@]} -gt 0 ]] || die "nothing to apply for $component"
series=$( { cat "${patches[@]}" /dev/null; for f in "${overlay_files[@]}"; do printf '%s\n' "$f"; cat "$overlay_dir/$f"; done; } | sha256sum | cut -d' ' -f1)
head=$(git -C "$src" rev-parse HEAD)

if [[ -f $stamp ]]; then
	# shellcheck source=/dev/null
	source "$stamp"
	if [[ ${STAMP_SERIES:-} == "$series" && ${STAMP_HEAD:-} == "$head" ]]; then
		log "$component: patches and overlay already applied ($head)"
		exit 0
	fi
fi

[[ -z $(git -C "$src" status --porcelain --untracked-files=no) ]] ||
	die "$src has uncommitted changes; commit them and run scripts/export-patches.sh $component, or discard them"
git -C "$src" cat-file -e "$base^{commit}" 2>/dev/null ||
	die "$src does not contain $tag ($base); run scripts/fetch.sh $component"
if [[ $head != "$base" && ${STAMP_HEAD:-} != "$head" && -z ${BSP_FORCE_PREPARE:-} ]]; then
	die "$src is at $head, which is neither $tag nor the last prepared state; check out $tag first or set BSP_FORCE_PREPARE=1"
fi

for f in "${overlay_files[@]}"; do
	git -C "$src" cat-file -e "$base:$f" 2>/dev/null &&
		die "overlay file $f already exists in $tag; changes to upstream files belong in $patch_dir"
done

log "$component: ${#patches[@]} patches and ${#overlay_files[@]} overlay files on $tag"
git -C "$src" "${git_id[@]}" checkout --quiet -B "$branch" "$base"
# Leave the tree at the pristine tag if anything below fails, so the next run
# can start over without manual cleanup.
prepared=
reset_on_failure() {
	[[ -n $prepared ]] && return 0
	git -C "$src" am --abort >/dev/null 2>&1 || true
	git -C "$src" "${git_id[@]}" checkout --quiet -B "$branch" "$base"
	log "$component: tree reset to $tag after the failure above"
}
trap reset_on_failure EXIT
if [[ ${#patches[@]} -gt 0 ]]; then
	git -C "$src" "${git_id[@]}" am --3way --whitespace=nowarn "${patches[@]}" ||
		die "$component: patch series did not apply cleanly"
fi
if [[ ${#overlay_files[@]} -gt 0 ]]; then
	for f in "${overlay_files[@]}"; do
		[[ ! -e $src/$f ]] || die "overlay file $f is also created by a patch; keep one copy"
		install -D -m "$(stat -c %a "$overlay_dir/$f")" "$overlay_dir/$f" "$src/$f"
	done
	(cd "$src" && git add -- "${overlay_files[@]}")
	git -C "$src" "${git_id[@]}" commit --quiet -m "atk-dlrk3588-bsp: add $component overlay files

Files copied verbatim from atk-dlrk3588-bsp/$component/overlay; edit them
there (or here and run scripts/export-patches.sh $component)."
fi
prepared=1
head=$(git -C "$src" rev-parse HEAD)
mkdir -p "$BSP_BUILD"
printf 'STAMP_SERIES=%s\nSTAMP_HEAD=%s\n' "$series" "$head" > "$stamp"
log "$component: prepared at $head"
