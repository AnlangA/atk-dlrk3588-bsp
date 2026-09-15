# Slint 显示实施与验收

**当前结果：J23 的 5.5 寸 1080×1920 MIPI 屏已点亮，使用 Mali-G610 GPU，无桌面系统。
CPLL / 375 MHz 的 DSI 系统时钟已固化到设备树，并通过正式部署后的重启验证。**

用户在 2026-09-15 晚间确认“现在界面有ui”。自动测试另行证明 GPU 执行、DRM
提交、面板控制和输入事件；两类证据分开记录，不用 GPU 截图冒充屏幕照片。

| 文档 | 内容 |
| --- | --- |
| [README](README.md) | 首次准备、构建、部署、运行、诊断和回滚 |
| [ARCHITECTURE](ARCHITECTURE.md) | 硬件映射、时钟、生命周期、GPU 缓冲区和文件职责 |
| [BRINGUP](BRINGUP.md) | 按阶段保留的排障过程、原厂对照和实验边界 |
| [验证索引](validation/README.md) | 每份数据的时间、范围和解释 |
| [内核补丁索引](../../linux/patches/README.md) | 补丁目的、依赖与验证 |

## 需求与验收

| 需求 | 实现 | 证据/结论 |
| --- | --- | --- |
| 无桌面直接显示 | Slint LinuxKMS + FemtoVG + EGL/GBM | 无 X11/Wayland compositor 依赖 |
| 必须使用 GPU | Panthor + Mesa + Mali-G610，运行时核查 GL 身份 | GPU 执行时间增加，软件 renderer 被拒绝 |
| J23 1080p 面板 | VP3 → dsi0 → DCPHY0 → HX8399 | 接线、ADC7、DCS ID 和用户实屏反馈一致 |
| 消除有背光无图像 | `CLK_DSIHOST0` 显式选 CPLL / 375 MHz | 用户确认正确 UI；配置经重启保留 |
| 简单交互 | 指标、Count、Pause/Resume、Reset | Slint 指针单测及板上 evdev 注入通过 |
| 启动与权限 | 专用非 root systemd 服务、seatd | 自动启动，CapEff=0，验收时 NRestarts=0 |
| 日志与诊断 | GPU 身份/帧/截图/动作日志，按需 DCS 状态 | 正常读回及错误请求后的恢复均验证 |
| 可重复维护 | 固定依赖、外部模块、标准 DT、可导出补丁 | 构建检查、schema、checkpatch、备份和校验清单 |

## 验证基线

正式部署后的 boot ID 为 `73928060-bd62-47cb-9d6a-175e21e276fc`：

- Linux `7.2.5-atk-dlrk3588+ #5`；Panthor 1.8.0；Mesa 26.0.8-1ubuntu0.3。
- Slint 1.17.1，Mali-G610 MC4 (Panfrost)，OpenGL ES 3.1。
- DSI 父时钟 cpll、375000000 Hz；临时时钟模块未加载。
- 原始五秒采样 GPU 执行时间增加 5755167 ns，GPU PNG 为 1080×1920、101372 字节。
- 面板 ID=83990c、status=80730400、连续错误计数=0；诊断结束后 VIDEO_MODE=3。
- Count、Pause/Resume、Reset 注入通过；taint=4096，仅树外模块位。
- 应用 rustfmt/Clippy、6 个 Rust 测试、3 个启动项测试、2 个 ADC 测试通过。
- 显示内核补丁 checkpatch、面板 W=1 和相关设备树 schema 检查通过。

原始验收数据见 [gpu-after-reboot.json](validation/gpu-after-reboot.json)。后续整理
复核记录单独保存，不覆盖这次重启的数据或截图；版本和 SHA256 见
[release-manifest.json](validation/release-manifest.json)。数值是记录，不是性能承诺。

维护整理时再次通过宿主机检查，验证上游 crate 加唯一补丁后与本地后端全部
27 个文件一致。验证脚本改为显式请求 GPU 重绘，消除 Pause 状态下的误判；
“暂停时检查 GPU 并保持暂停”及“从暂停开始完成按钮测试”均已实机通过，结束后
恢复 Live。只读复核的已安装 Image、DTB 和应用哈希与本地产物一致，服务仍无重启。
详见 [维护复核](validation/maintenance-check.json)。

## 正式修复与保留限制

DSI 系统时钟配置是本次实际出图的关键；SPLL 的物理频率尚未测量，不宣称已证实
“频率减半”。EoT、AFBC 协商、模式等待、桥对象释放及 DCS 读回是分别发现并验证
的问题，不能将其中任一项单独等同于实屏点亮。

DCS 按需读取会短暂暂停视频并可能跳帧；正常应用不轮询。RGB 原始读数仍为零，
扫描行也可能停在相同边界，它们不构成图像判据。正式范围只有当前 J23 1080p
组合；其他面板、J24、HDMI 实屏、旋转、多屏和长期热插拔需要独立验证。

## 后续维护顺序

1. 从固定源码与补丁构建，先执行宿主机检查和 DT schema 检查。
2. 内核/模块/DTB 一起打包，应用通过独立 Slint 部署入口更新。
3. 核对备份、实际启动项与文件校验值，验证重启后的时钟和服务。
4. 运行 GPU/面板检查，再按需运行输入注入和实屏验收。
5. 保留每次验证的范围、版本、时间和校验值；实验失败同样保留原始记录。

上述顺序用于未来升级，不表示当前仍有部署步骤待完成。
