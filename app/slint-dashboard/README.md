# Slint 无桌面 GPU 状态界面

ATK-DLRK3588 的 **J23、5.5 寸 1080×1920 MIPI 屏已实屏点亮**。正式程序使用
Slint 1.17.1 / LinuxKMS / FemtoVG / OpenGL ES，运行在主线 Panthor + Mesa 的
Mali-G610 GPU 上，专用非 root 账户启动，不依赖桌面系统。

| 需要了解 | 文档 |
| --- | --- |
| 硬件、时钟、驱动和应用设计 | [实现说明](ARCHITECTURE.md) |
| 已完成事项和验收边界 | [实施与验收](PLAN.md) |
| 黑屏定位、原厂对照和历史实验 | [调试档案](BRINGUP.md) |
| 数据、版本和校验值 | [验证索引](validation/README.md) |
| 内核/Slint 补丁来源 | [内核补丁](../../linux/patches/README.md)、[Slint 后端补丁](patches/README.md) |

## 当前运行配置

| 项目 | 值 |
| --- | --- |
| 板卡 / 系统 | 正点原子 ATK-DLRK3588 / Ubuntu Base 26.04.1 ARM64 |
| 内核 | Linux 7.2.5-atk-dlrk3588+ |
| 输出 | VP3 → SoC dsi0 → J23，DRM 名称 DSI-1 |
| 面板 / 触摸 | HX8399 / GT911，I²C5 地址 0x5d |
| DSI 系统时钟 | **CPLL / 4 = 375 MHz**，固化在 J23 DTS |
| 像素时钟 / 刷新率 | 118.8 MHz / 约 53.84 Hz |
| GPU / 缓冲区 | Mali-G610、OpenGL ES 3.1；XRGB8888 / AFBC |
| 运行服务 | slint-dashboard.service；User=slint-display；SupplementaryGroups=video render |
| 正式启动项 | bsp；Image 和 DTB 在 /boot/atk-dlrk3588-bsp/ |

J23 在原厂原理图上叫 MIPI DSI1，不能据此选择 Linux 的 dsi1（那对应 J24）。
ADC7 约 1410 能识别 1080p 屏，不能识别插座。本项目只交付该 J23 profile。

## 1. 首次准备

下列 `make` 命令在 BSP 根目录执行。先按照 [根 README](../../README.md) 准备固定
源码和工具链，在 `local.env` 配置 BOARD_HOST、BOARD_SSH_OPTS、AARCH64_CC 等。
例子使用已有 SSH 别名 `rk3588`；新机器应替换为自己的连接配置。

实际验证工具链为 Rust/Cargo 1.98.1、LLVM 21、SDK AArch64 GCC 10.3.1。
Cargo.toml 声明的最低 Rust 为 1.92，最低版本没有单独验收。Rust 1.98.1 的目标
链接命令使用随工具链提供的 LLD；仅强制使用 SDK 的旧 BFD 链接器可能不支持
Ubuntu 目标库中的 RELR。宿主机链接烟雾检查及版本保存在维护复核记录中。

宿主机依赖：

```sh
sudo apt-get install --no-install-recommends pkg-config rsync \
    libinput-dev libudev-dev libxkbcommon-dev libseat-dev libfontconfig-dev \
    libgbm-dev libegl-dev libgles-dev fonts-dejavu-core
rustup target add aarch64-unknown-linux-gnu
```

将运行依赖脚本复制到已经可启动的 Ubuntu Base 开发板并执行：

```sh
scp board/prepare-display.sh rk3588:/var/tmp/prepare-display.sh
ssh -t rk3588 sudo bash /var/tmp/prepare-display.sh
```

脚本安装 Mesa/EGL/GLES/GBM、libinput、libseat/seatd、字体和 Ubuntu 官方固件包，
不安装桌面。内核未启用压缩固件加载时，它将 Mali CSF `.zst` 解压到
`/lib/firmware/arm/mali/arch10.8/mali_csffw.bin`。更新固件包后重新运行脚本同步。

导出 sysroot 还需要开发板上的开发包；在板上执行：

```sh
sudo apt-get install --no-install-recommends libc6-dev libinput-dev libudev-dev \
    libxkbcommon-dev libseat-dev libfontconfig-dev libgbm-dev libegl-dev \
    libgles-dev pkg-config rsync
```

`local.env` 由 scripts/lib.sh 在脚本启动时加载，其中无条件赋值会覆盖同名环境
变量。建议直接在该文件选定 profile；若希望命令行可覆盖，可使用
`BOARD_DTB=${BOARD_DTB:-auto}` 的默认值写法。凭据文件必须保存在 Git 忽略目录中。

## 2. 从源码构建并首次部署

```sh
make fetch
make linux
make app                 # BSP 部署包同时包含原有 rs485-test
make display-sysroot
make display
make check-display
make display-detect
make package
make deploy
make deploy-display
```

执行前在 `local.env` 中选择以下一项：

```sh
BOARD_DTB=auto
# 或者离线明确选择：
# BOARD_DTB=rk3588-atk-dlrk3588-mipi-1080p.dtb
```

`auto` 在打包时经 SSH 读取 ADC7；不支持的 profile 或不稳定数据会报错，不套用
1080p 初始化。新内核配置需重新合并时使用 `BSP_RECONFIGURE=1 make linux`。
`make package` 依赖已生成的内核、树外模块、DTB 和串口应用，不包含 Slint 程序；
Slint 由 `make deploy-display` 单独安装。

| 产物 | 位置 |
| --- | --- |
| 内核 | build/linux/arch/arm64/boot/Image |
| J23 DTB | build/linux-dts/rk3588-atk-dlrk3588-mipi-1080p.dtb |
| panel 模块 | build/linux-modules/panel-alientek-md0550.ko |
| Slint 可执行文件 | build/slint/aarch64-unknown-linux-gnu/release/slint-dashboard |
| BSP 部署包 | build/deploy/atk-dlrk3588-bsp-<release>.tar.gz |
| sysroot / 包清单 | build/slint-sysroot/ / packages.tsv |

打包会把选中的 DTB 命名为包内 `boot/rk3588-atk-dlrk3588.dtb`。必须配套部署内核、
模块和 DTB；相同 uname release 不足以证明两个构建的模块兼容，应核对发布清单。
现有 U-Boot 已可启动，本次显示实现不要求刷写它。

`make deploy` 默认安装并保留旧启动项，**不自动重启**。内核/模块/DTB 更新后，在
板上执行 `sudo systemctl reboot`，随后核对实际新启动状态，再运行验收。
也可使用 `make deploy DEPLOY_ARGS=--reboot` 明确要求安装后重启。

## 3. 日常更新与配置

仅更新界面：

```sh
make display
make check-display
make deploy-display
```

安装器先校验 SHA256、检查依赖、备份旧程序/服务/配置，再替换程序并重启服务。
`DISPLAY_DEPLOY_ARGS=--no-start` 安装并启用，但不触发启动/重启。已有
`/etc/default/slint-dashboard` 在升级时保留，模板变更不会自动覆盖用户配置。

需要在同时连接 HDMI 时仍固定 J23，可在板上的配置文件设置：

```sh
SLINT_SCALE_FACTOR=2
SLINT_DRM_OUTPUT=DSI-1
```

然后 `sudo systemctl restart slint-dashboard`。不设置输出时选择首个已连接
connector；输出自动选择不等于多屏策略。模式使用 `SLINT_DRM_MODE` 的索引，
不是分辨率字符串；`SLINT_DRM_OUTPUT=list` / `SLINT_DRM_MODE=list` 用于临时列举，
列举后进程退出，完成后应移除 list 配置，避免服务反复列举。

Pause 暂停指标采样；Count 仍可操作；Reset 只清零计数。缩放、显示旋转和触摸
坐标旋转是不同设置，当前验收基线为 scale=2、未旋转的竖屏。

## 4. 日志、测试与截图

板上只读核查：

```sh
systemctl status slint-dashboard
sudo journalctl -u slint-dashboard -b --no-pager
cat /sys/class/drm/card*-*/status
sudo cat /sys/kernel/debug/clk/clk_dsihost0/clk_parent
sudo cat /sys/kernel/debug/clk/clk_dsihost0/clk_rate
/usr/local/bin/slint-dashboard --metrics
```

日志含 `DRM_OUTPUT`、`GPU_READY`、`GPU_SCANOUT`、`GPU_FRAME`、`GPU_CAPTURE`、
`UI_ACTION`；`GPU_REQUIRED` 表示上下文不符合强制 GPU 要求。帧日志每 60 次绘制
记录一次，不能将日志间隔当作显示故障。

宿主机执行：

```sh
make check-display
make test-display
make test-display DISPLAY_TEST_ARGS=--touch
```

`make check-display` 运行 rustfmt、Clippy、6 个 Rust 测试及 5 个启动项/ADC 测试。
GPU 测试检查实际 GL 上下文、非 root/CapEff、GPU 执行计数、AFBC、截图、CPLL、
面板状态及读回后恢复的视频模式。测试显式请求重绘，所以暂停界面也能验证 GPU，
普通测试保持 Pause 状态。`--touch` 会注入 Goodix 事件，先恢复 Live，再测试按钮，
成功后留下 Count=0、Pause=false；它是软件事件注入，不冒充人工触摸验收。

截图优先使用常驻服务，避免两个进程争用 DRM master：

```sh
sudo systemctl kill --kill-whom=main -s SIGUSR1 slint-dashboard
sudo stat /run/slint-dashboard/frame.png
```

截图在下次定时器触发绘制后完成，可能需约 1 秒；权限由服务 UMask=0077 限制。
通过 root 复制到供当前用户读取的临时位置后再下载，不要放宽整个设备目录权限。
该 PNG 是 GPU 回读。CLI 还支持 `--capture FILE.png`（一帧后退出）和
`--test-pattern`（五色，每色 20 秒）；独立运行需要先停止主服务，并提供与主服务
相同的 video/render 组、seatd 和可写目录。结束后重新启动主服务。

按需检查面板：

```sh
sudo cat /sys/kernel/debug/fde20000.dsi.0/status
```

此读取会清除 DSI 错误计数，并短暂暂停视频，可能跳帧；不要后台高频轮询。
ID 应为 83 99 0c、格式 77、power=9d、self-diagnostic=c0；最终测试状态为
80730400、连续错误为零。RGB=0 或两次扫描行相同均不是黑屏判据。
面板关闭时返回 ENODEV。正式应用没有裸寄存器访问；根权限测试只读一个硬件模式
寄存器以验证驱动恢复视频，细节见实现说明。

## 5. 排障与回滚

| 现象 | 优先核查 |
| --- | --- |
| 有背光、无图像 | 是否启动了正确 J23 DTB；DSI 父时钟是否 cpll、375 MHz；GPU_READY 与 AFBC 是否正常 |
| 服务停留在启动阶段 | 等待脚本是否找不到 Panthor、固件或所选 connector；检查 journal/kernel 日志 |
| GPU_REQUIRED | 实际 GL renderer、Mesa/固件版本、GPU/pd_gpu 电源；不要切到软件渲染掩盖问题 |
| DCS 超时/读数错乱 | 核对配套 DSI2 补丁和模块；避免多个诊断进程同时读取；不要边扫描边随意改寄存器 |
| 触摸异常 | J23 的 I²C5 / 0x5d、evdev 范围、scale/rotation；错误的可选 Goodix 固件会改变坐标 |
| 更新后没有采用新配置 | 核对实际 boot ID、extlinux DEFAULT、DTB SHA256、模块及保留的 /etc/default 配置 |

应用备份在 `/var/backups/slint-dashboard.*`，BSP 备份在
`/var/backups/atk-dlrk3588-bsp/<时间>/`。具体成功发布的备份和哈希见发布清单。
`--remove` 用于卸载程序和服务、保留配置/用户/备份，不等于恢复上一版本。

仅停止界面并恢复 tty1：

```sh
sudo systemctl disable --now slint-dashboard
sudo systemctl start getty@tty1
```

应用回滚应从选定备份恢复其中的程序、unit、等待脚本与配置，再 daemon-reload
并重启服务。内核故障可从 U-Boot 串口菜单选择保留的 rust 启动项；完整版本回滚
必须同时恢复匹配的 Image、DTB 和模块。**旧启动项共享 /lib/modules/<release> 时，
单独切换菜单不等同于完整回滚**。BSP 备份内保存了旧模块目录和 boot-before.tar.gz。
恢复前先保留当前状态并检查备份内容，不把历史诊断项 slint 当成当前正式启动项。

使用 `df -h /boot` 检查空间。替换不同 Image 要容纳旧文件和 Image.new；若 Image
完全相同，安装器跳过复制，允许只更新模块/DTB。不要为腾空间直接删除唯一可用内核。
`board/install-display-dtb.py` 是早期独立 DTB 诊断工具，默认交付流程不用它。

## 6. 来源与许可证

应用为 [GPL-3.0-only](LICENSE)；后端原始许可证保留；其余文件按各自 SPDX。
本地补丁和 panel binding 尚未提交上游。运行依赖版本随 Ubuntu 更新可能变化，
当前验收版本以 [发布清单](validation/release-manifest.json) 为准。

- [原厂 MIPI 识别表](https://wiki.alientek.com/docs/Boards/Linux/DLRK3588/DLRK3588%20%E5%BF%AB%E9%80%9F%E4%BD%93%E9%AA%8C%E6%89%8B%E5%86%8C/function_test/3.3_mipi/)
- [原厂 J23/J24 映射](https://wiki.alientek.com/docs/Boards/Linux/DLRK3588/DLRK3588%20%E7%A1%AC%E4%BB%B6%E5%8F%82%E8%80%83%E6%89%8B%E5%86%8C/describe/3.15/)
- [Slint LinuxKMS 后端](https://docs.slint.dev/latest/docs/slint/guide/backends-and-renderers/backend_linuxkms/)
- 本地 SDK：`/home/a/workspace/rk3588/linux_sdk/atk-rk3588_linux_release_v1.2_20250104`，主要参考 `rk3588-atk-lcds.dtsi`、`dw-mipi-dsi2-rockchip.c` 和 `resource_hwid.c`。
