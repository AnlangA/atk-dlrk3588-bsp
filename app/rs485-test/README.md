# rs485-test

Rust UART/RS485 与字符设备驱动的应用和回归测试程序。这是一个独立的 Cargo
工程，不依赖内核树、U-Boot 或仓库里的构建脚本；`make app` 只是它的交叉编译快捷方式。

## 单独编译

```sh
cd app/rs485-test

# 板子（AArch64）：需要 rustup target 和一个 AArch64 GCC 作链接器
rustup target add aarch64-unknown-linux-gnu
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
    cargo build --locked --release --target aarch64-unknown-linux-gnu

# 本机（例如作为 PC 端 RS485 对端），或直接在开发板上原生编译
cargo build --locked --release
```

产物在 `target/<triple>/release/`：`rs485-test`（应用，子命令 `loopback`、`uart`、
`peer`、`chardev`）和 `driver-test-init`（仅供 QEMU 测试作 init）。唯一的依赖是
`libc`，由 `Cargo.lock` 锁定；MSRV 1.85，与内核所需的 Rust 版本无关。

## 测试

```sh
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
cargo fmt --check
```

`cargo test` 包含协议/CRC 单元测试、真实 PTY 上的分片与超时测试，以及直接编译
内核侧源码的测试（`linux/drivers/rust_chardev/ring.rs`、
`linux/drivers/rust_dw_uart/config.rs`、`linux/overlay/rust/kernel/serial/dma/state.rs`）。
`build.rs` 在仓库内自动找到这些文件；把本目录复制到别处单独使用时，它们会被跳过并
给出 `cargo:warning`，可用 `RS485_TEST_BSP_ROOT=/path/to/atk-dlrk3588-bsp` 指回仓库。

## 部署

仓库根目录执行 `make deploy-app`（`DEPLOY_ARGS=--check` 顺带在板上跑一次
`chardev` 测试），或手动：

```sh
scp target/aarch64-unknown-linux-gnu/release/rs485-test ubuntu@<board>:/tmp/
ssh ubuntu@<board> 'sudo install -m 0755 /tmp/rs485-test /usr/local/bin/rs485-test'
```

驱动未变时不需要重启。板上用法见 [linux/docs/rust-uart-rs485.rst](../../linux/docs/rust-uart-rs485.rst)
的 “Controller tests” 与 “Character-device tests”。
