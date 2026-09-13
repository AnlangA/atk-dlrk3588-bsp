#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Host-side checks that need no board and no kernel build: shell syntax,
# ShellCheck when installed, Python byte-compilation, and the application's
# rustfmt, Clippy and unit/PTY tests.
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
need_cmd cargo python3

cd "$BSP_ROOT" || die "cannot enter $BSP_ROOT"
shell_files=(scripts/*.sh board/*.sh tests/*.sh)
log "shell syntax"
for file in "${shell_files[@]}"; do bash -n "$file"; done
if command -v shellcheck >/dev/null; then
	log "shellcheck"
	shellcheck -x -P SCRIPTDIR "${shell_files[@]}"
else
	log "shellcheck not installed; skipped"
fi
log "python syntax"
python3 -m py_compile tests/qemu-test.py
rm -rf tests/__pycache__

cd "$BSP_ROOT/app/rs485-test" || die "missing app/rs485-test"
export CARGO_TARGET_DIR=$APP_OUT
log "rustfmt"
cargo fmt --check
log "clippy"
cargo clippy --locked --all-targets -- -D warnings
log "host tests"
cargo test --locked
log "all checks passed"
