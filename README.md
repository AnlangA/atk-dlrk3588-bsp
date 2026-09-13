# ATK-DLRK3588 BSP

面向正点原子 ATK-DLRK3588（RK3588）的独立板级支持工程。它把板级配置、Rust UART
控制器驱动、Rust 字符设备、测试程序和应用集中放在一个仓库里，参照 Zephyr
out-of-tree 工程的组织方式，直接在 **未修改的主线 Linux 与 U-Boot 发布版本**
上编译，不再依赖个人 fork 分支。

基线由 [manifest.env](manifest.env) 固定：

| 组件 | 上游 | 版本 |
| --- | --- | --- |
| Linux | kernel.org stable | `v7.2.5` |
| U-Boot | u-boot/u-boot | `v2026.10-rc4` |
| 固件 | rockchip-linux/rkbin `50942f0b` | BL31 v1.46，DDR v1.17（板级参数见下） |

工具链：Rust 1.98、Clang/LLVM 21、bindgen 0.72、AArch64 GCC（U-Boot 与应用链接）。

## 工程结构

```text
atk-dlrk3588-bsp/
├── manifest.env            # 固定上游源码版本与固件校验值
├── Makefile                # make fetch / linux / uboot / app / check / qemu / package / deploy
├── scripts/                # 各目标对应的脚本，可单独运行
├── linux/
│   ├── drivers/            # 树外 Rust 模块：rust_dw_uart、rust_chardev（Kbuild M=）
│   ├── dts/                # 树外设备树 rk3588-atk-dlrk3588.dts（Kbuild M=）
│   ├── configs/            # 在 arm64 defconfig 上合并的配置片段
│   ├── overlay/            # 复制进内核树的新增文件：rust/kernel/serial*.rs、dmaengine.rs、C helpers
│   ├── patches/            # 对既有上游文件的最小改动（git am）
│   └── docs/               # 驱动设计与使用文档、/dev/rust-chardev ABI
├── u-boot/
│   ├── overlay/            # 板级设备树、board/rockchip/atk_dlrk3588、defconfig、板级头文件
│   ├── patches/            # 仅注册 TARGET_ATK_DLRK3588 的 Kconfig 补丁
│   └── ddrbin_param.txt    # 板级 DDR 参数（LPDDR4/LPDDR4X 上限 1560 MHz）
├── app/rs485-test/         # 应用与测试：rs485-test、QEMU init、宿主机单元/PTY 测试
├── board/                  # 板上运行文件：UART3 绑定脚本、systemd 服务、udev 规则、安装脚本
└── tests/                  # QEMU 模块生命周期测试、TAP 入口、板上冒烟测试
```

### 哪些内容在树外，哪些必须打补丁

| 内容 | 方式 | 原因 |
| --- | --- | --- |
| `rust_dw_uart`、`rust_chardev` 模块 | `linux/drivers/`，`make M=` 树外编译 | 只使用 `kernel` crate API，不需要树内 Kconfig |
| 板级设备树 | `linux/dts/`，`make M=` 用内核自带 dtc 编译 | 仅 `#include <arm64/rockchip/rk3588.dtsi>` 与树内写法不同 |
| `rust/kernel/serial.rs`、`serial/dma.rs`、`dmaengine.rs`、C helpers | `linux/overlay/` 原样复制进内核树 | 是 `kernel` crate 的一部分，必须随内核编译，但都是新增文件 |
| `lib.rs`、`miscdevice.rs`、`clk.rs`、`kiocb.rs`、`barrier.rs`、`bindings_helper.h`、`helpers.c`、`pl330.c` 的改动 | `linux/patches/` | 修改上游既有文件，只能以补丁形式存在 |
| U-Boot 板级文件 | `u-boot/overlay/` | 全部是新增文件 |
| U-Boot `rk3588/Kconfig` 注册目标 | `u-boot/patches/` | 修改上游既有文件 |

宿主机单元测试直接编译 `linux/drivers/` 与 `linux/overlay/` 中的内核侧源码
（环形缓冲、寄存器编码、DMA 完成状态机），因此不需要先准备内核树。

## 快速开始

```sh
cp local.env.example local.env   # 按本机填写工具链路径、开发板地址（可选）
make fetch                       # 浅克隆 Linux v7.2.5、U-Boot v2026.10-rc4，下载 rkbin 固件
make linux                       # 打补丁、复制 overlay、配置并编译内核、树外模块和 DTB
make uboot                       # 打补丁、复制 overlay、生成板级 DDR blob 并编译 U-Boot
make app                         # 交叉编译 rs485-test 与 driver-test-init（不需要内核树）
make check                       # shellcheck、rustfmt、clippy、宿主机测试
make qemu                        # 在 QEMU 中加载 ARM64 模块并运行字符设备测试
make package                     # 生成 build/deploy/ 部署包
```

各目标相互独立：`make app` 与 `make check` 只需要 cargo 和交叉链接器，`make uboot`
不依赖内核；`app/rs485-test/` 本身是可单独编译的 Cargo 工程，复制到任何地方
`cargo build` 即可，见 [app/rs485-test/README.md](app/rs485-test/README.md)。

产物：

- 内核 `build/linux/arch/arm64/boot/Image`，版本 `7.2.5-atk-dlrk3588+`；
- 设备树 `build/linux-dts/rk3588-atk-dlrk3588.dtb`；
- 模块 `build/linux-modules/rust_dw_uart.ko`、`rust_chardev.ko`，树内模块随 `make package` 一并安装；
- U-Boot `build/u-boot/u-boot-rockchip.bin`（idbloader + u-boot.itb，写入扇区 64）；
- 应用 `build/app/aarch64-unknown-linux-gnu/release/rs485-test`。

`make linux` 内部执行的树外编译等价于：

```sh
make -C external/linux O=build/linux ARCH=arm64 LLVM=-21 \
     M=$PWD/linux/drivers MO=$PWD/build/linux-modules modules
make -C external/linux O=build/linux ARCH=arm64 LLVM=-21 \
     M=$PWD/linux/dts MO=$PWD/build/linux-dts
```

## 烧录与部署

### Linux、模块与应用（开发板已运行 Ubuntu）

```sh
make package
make deploy                      # 需要 BOARD_HOST=user@addr，可加 DEPLOY_ARGS="--reboot"
```

`scripts/deploy-board.sh` 通过 SSH 上传部署包并在板上执行 `board/install.sh`：校验
SHA-256，备份原 `/boot/extlinux` 与旧文件到 `/var/backups/atk-dlrk3588-bsp/<时间>/`，
安装 `/lib/modules/<release>/`、`/boot/atk-dlrk3588-bsp/{Image,dtb}`、
`/usr/local/bin/rs485-test`、`bind-uart3.sh`、udev 规则和 `rust-uart3.service`，
再在 extlinux 菜单新增并默认选择 `bsp` 启动项（`--no-default` 只新增不切换）。
原有启动项保留，可在 U-Boot 菜单回退。`/boot` 只有 128 MiB，放不下第三个
Image 时脚本会列出现有目录，用 `--boot-dir <目录>` 指定替换其中一个。

重启后在板上验证：

```sh
sudo /var/tmp/atk-dlrk3588-bsp/payload/board-smoke.sh 7.2.5-atk-dlrk3588+
```

只更新应用（驱动未变，不必重启）：

```sh
make app && make deploy-app DEPLOY_ARGS=--check   # 安装到 /usr/local/bin 并在板上跑一次 chardev 测试
```

它检查内核版本、`/dev/rust-chardev`、UART3 绑定到 `/dev/ttyRU0`、9600–1500000
波特率 DMA 内部回环，并打印 `/sys/kernel/debug/rust_dw_uart/dma` 计数。外部 RS485
双机测试见 [linux/docs/rust-uart-rs485.rst](linux/docs/rust-uart-rs485.rst)。

### U-Boot

```sh
make flash-uboot FLASH_ARGS=--board          # SSH 到运行中的开发板，写 eMMC 扇区 64 并回读校验
make flash-uboot FLASH_ARGS="--sd /dev/sdX"  # 写读卡器中的 TF 卡
make flash-uboot FLASH_ARGS=--maskrom        # Maskrom 模式，需 RK_LOADER 与 rkdeveloptool/upgrade_tool
```

U-Boot 位于第一个 GPT 分区之前的 32 MiB 区域，写入不会触及分区内容。

### DDR 固件

`rkbin` 的 `rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.17.bin` 经
`tools/ddrbin_tool rk3588 u-boot/ddrbin_param.txt` 处理后，与原厂 SDK 中实际烧录的
blob 逐字节一致（`lp4_freq`/`lp4x_freq` 改为 1560）。`make uboot` 会校验生成结果的
SHA-256；修改参数后需同步更新 `manifest.env` 中的 `BOARD_DDR_SHA256`。`ddrbin_tool`
是 x86-64 二进制，其他主机可用 `ROCKCHIP_TPL=` 直接指定现成 blob。

## 开发流程

- 树外文件（`linux/drivers`、`linux/dts`、`app`、`board`）直接修改后重新 `make`。
- 内核树内改动在 `external/linux`（分支 `atk-dlrk3588-bsp`）里正常 `git commit`，然后
  `make export-patches`：overlay 文件从树里复制回 `linux/overlay/`，其余提交重新导出为
  `linux/patches/*.patch`。在树里新建的文件会进入补丁，若希望保持为普通文件，把它
  移到 `overlay/` 即可。U-Boot 同理。
- `scripts/prepare.sh` 在补丁或 overlay 变化时会从原始 tag 重新应用；树里有未提交改动时
  拒绝执行，避免覆盖工作。
- `LINUX_SRC=`/`UBOOT_SRC=` 可以指向已有的 git 检出（须包含对应 tag），代替 `external/`。

## 验证记录

2026-09-13 在本工程内以主线源码完成：

- `make fetch`：kernel.org `v7.2.5`、GitHub `v2026.10-rc4`、rkbin 三个文件校验通过，
  共约 2 分钟。
- 补丁与 overlay 应用后，内核树 `rust/`、`drivers/dma/pl330.c`、`samples/` 与 fork 分支
  `atk-rk3588-7.2.5` 逐字节相同；U-Boot 七个板级文件与 fork 分支 `atk-rk3588` 相同。
  从原始 tag 重新执行 `prepare` 得到相同的 git tree 哈希。
- `make linux`（24 线程 5 分 45 秒，无警告）：`Image` 41,253,376 字节，版本
  `7.2.5-atk-dlrk3588+`；树外 `rust_dw_uart.ko`、`rust_chardev.ko` 由 Kbuild `M=` 以
  `RUSTC [M]` 编译，vermagic 与内核一致；树外 DTB 与此前部署在板上的 DTB
  **逐字节相同**（SHA-256 `17f3b31c…`）。
- `make uboot`：`idbloader.img` 210944、`u-boot.itb` 1377280、`u-boot-rockchip.bin` 9733120
  字节，与已在板上验证的构建大小一致；派生 DDR blob SHA-256 与原厂一致；BL31 来自 rkbin。
- `make check`：13 个单元测试与 2 个 PTY 测试通过，Clippy `-D warnings`、rustfmt、
  ShellCheck 通过。
- `make qemu`：QEMU virt 加载主线内核与两个树外模块，字符设备测试与模块加载/卸载
  各 3 轮通过（`RUST_DRIVER_QEMU_RESULT=PASS`）。
- `make package`：部署包 133 MiB，1680 个文件的 SHA-256 清单校验通过；`board/install.sh`
  的 extlinux 编辑逻辑用样例配置验证了新增、替换与首次安装三种路径。

本次开发板处于断电状态，`make deploy`/`make flash-uboot` 未在实机执行；产物与此前实测
通过的 fork 构建同源同配置。树外模块会给内核加上 `O` taint 标志（`/proc/sys/kernel/tainted`
为 4096），这是树外编译的固有结果，不表示错误。

相对 fork 构建的配置差异：不再有 `SERIAL_RUST_DW`/`RUST_CHARDEV` 符号（模块改为树外），
`SAMPLES` 关闭，`INIT_STACK_ALL_ZERO=y`（Clang 下 defconfig 的默认值）。

## 来源

驱动、抽象层、设备树与测试程序来自 [AnlangA/linux `atk-rk3588-7.2.5`](https://github.com/AnlangA/linux/tree/atk-rk3588-7.2.5)
（提交 `30f7e3be48a1`…`44268fd8bbeb`），U-Boot 板级支持来自
[AnlangA/u-boot `atk-rk3588`](https://github.com/AnlangA/u-boot/tree/atk-rk3588)
（提交 `c3b7ec1fff0`…`aa90a5b4566`）。这两个分支保留原始提交历史；本仓库是它们在
主线上的树外形态。板级实测记录（DMA 回环、RS485 双向、取消/解绑、PIO 对照）保存在
原工作区的 `analysis/` 目录。

许可证：GPL-2.0（设备树为 GPL-2.0+ OR MIT），见 [LICENSE](LICENSE)。
