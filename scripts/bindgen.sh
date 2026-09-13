#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Kbuild invokes this executable for version checks and binding generation.
# Host RUST_LOG settings often belong to the invoking IDE/application. Do not
# apply them to bindgen's internal parser logs; keep bindgen's default filter.
# Clang diagnostics, bindgen errors, stdout and the exit status pass through.
set -euo pipefail

if [[ ${BINDGEN_RUST_LOG+x} ]]; then
	export RUST_LOG=$BINDGEN_RUST_LOG
else
	unset RUST_LOG
fi

exec "${BSP_BINDGEN_BIN:-bindgen}" "$@"
