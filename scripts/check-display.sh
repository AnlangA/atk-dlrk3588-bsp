#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Native checks require the documented host -dev packages.
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
export CARGO_TARGET_DIR=$BSP_BUILD/slint-host
python3 "$BSP_ROOT/tests/test-display-boot.py"
python3 "$BSP_ROOT/tests/test-panel-id.py"
python3 -m py_compile "$BSP_ROOT/board/test-display-gpu.py"
manifest=$BSP_ROOT/app/slint-dashboard/Cargo.toml
cargo fmt --manifest-path "$manifest" --check
cargo clippy --manifest-path "$manifest" --locked --all-targets -- -D warnings
cargo test --manifest-path "$manifest" --locked
