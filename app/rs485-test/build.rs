// SPDX-License-Identifier: GPL-2.0-only

//! Locates the kernel-side sources whose unit tests run on the host.
//!
//! Inside the BSP checkout they are found relative to this crate; a copy of
//! the crate taken elsewhere still builds and runs its own tests, and can
//! point at a checkout with `RS485_TEST_BSP_ROOT`.

use std::{
    env, fs,
    path::{Path, PathBuf},
};

/// (module name, path below the BSP root, extra attributes)
const KERNEL_SIDE: &[(&str, &str, &str)] = &[
    ("ring_tests", "linux/drivers/rust_chardev/ring.rs", ""),
    (
        "uart_config_tests",
        "linux/drivers/rust_dw_uart/config.rs",
        "",
    ),
    (
        "dma_state_tests",
        "linux/overlay/rust/kernel/serial/dma/state.rs",
        "#[allow(dead_code)]",
    ),
];

fn bsp_root(manifest_dir: &Path) -> PathBuf {
    println!("cargo:rerun-if-env-changed=RS485_TEST_BSP_ROOT");
    env::var_os("RS485_TEST_BSP_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| manifest_dir.join("../.."))
}

fn main() {
    let manifest_dir =
        PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR"));
    let root = bsp_root(&manifest_dir);

    let mut generated = String::new();
    let mut missing = Vec::new();
    for (name, relative, attributes) in KERNEL_SIDE {
        let path = root.join(relative);
        // `#[path]` in a generated file must be absolute; relative paths would
        // resolve against OUT_DIR.
        match path.canonicalize() {
            Ok(path) if path.is_file() => {
                println!("cargo:rerun-if-changed={}", path.display());
                let literal = path.to_str().expect("UTF-8 source path");
                generated.push_str(&format!(
                    "{attributes}\n#[path = {literal:?}]\nmod {name};\n"
                ));
            }
            _ => missing.push(*relative),
        }
    }
    if !missing.is_empty() {
        println!(
            "cargo:warning=kernel-side unit tests skipped, not found under {}: {} \
             (set RS485_TEST_BSP_ROOT to an atk-dlrk3588-bsp checkout)",
            root.display(),
            missing.join(", ")
        );
    }
    fs::write(out_dir.join("kernel_side_tests.rs"), generated).expect("write kernel_side_tests.rs");
}
