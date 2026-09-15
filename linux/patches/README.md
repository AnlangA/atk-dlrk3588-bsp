# Linux 补丁说明

基线为 manifest.env 固定的 Linux v7.2.5。`scripts/prepare.sh linux` 按文件名顺序
应用 `*.patch`，再复制 `linux/overlay/`。不要仅编辑 `external/linux` 而遗漏导出。

0001—0004 是项目原有串口/DMA基础；0005—0010 来自 Slint 显示 bring-up。
[树外面板驱动](../drivers/panel-alientek-md0550.c) 和
[J23 设备树](../dts/rk3588-atk-dlrk3588-mipi-1080p.dts) 不在本补丁序列中。
实际点亮关键的 CPLL / 375 MHz 配置位于该设备树。

| 序号 | 范围 | 修改目的 |
| --- | --- | --- |
| [0001](0001-rust-extend-miscdevice-kiocb-and-clk-for-the-serial-.patch) | 原有串口基础 | 扩展 Rust miscdevice/kiocb/clk API；支撑原串口抽象 |
| [0002](0002-rust-clk-let-an-exclusive-clock-holder-retune-its-ra.patch) | 原有串口基础 | 持有独占时钟引用时允许调整时钟速率 |
| [0003](0003-dmaengine-pl330-synchronize-completion-callbacks.patch) | 原有串口基础 | 同步 PL330 DMA 回调，配合停止/解绑 |
| [0004](0004-rust-add-dmaengine-module-and-DMA-barriers-for-seria.patch) | 原有串口基础 | Rust DMA engine 与 DMA 屏障支持 |
| [0005](0005-drm-bridge-dw-mipi-dsi2-validate-and-drain-read-resp.patch) | DSI 协议 | 识别短/长响应、返回实际长度、排空剩余 RX 数据 |
| [0006](0006-drm-rockchip-report-GEM-DMA-addresses-in-debug-outpu.patch) | DRM 诊断 | 使用 GEM print_info 输出 DMA 地址，支撑显示缓冲区核对 |
| [0007](0007-drm-bridge-dw-mipi-dsi2-wait-for-the-requested-opera.patch) | DSI 模式 | 枚举状态按相等比较，避免 COMMAND=2 被 VIDEO=3 位掩码误接受 |
| [0008](0008-drm-bridge-dw-mipi-dsi2-release-panel-bridge-resourc.patch) | 桥对象生命周期 | 为 managed panel bridge 配对 devres group，避免 detach 后重复释放 |
| [0009](0009-drm-rockchip-apply-the-RK3588-prescan-sync-width-min.patch) | VOP 时序 | RK3588 预扫描同步宽度最小为 8；保留实际视频 HSync |
| [0010](0010-drm-bridge-dw-mipi-dsi2-quiesce-video-while-receivin.patch) | DSI 读事务 | 读回期间保持命令模式，成功/错误均恢复视频；允许跨帧边界等待 |

0010 使用 0007 纠正后的枚举语义，并集中模式切换检查；两者分别记录不同问题。
0008 还需配合树外 panel 的 `dsi->attached` 判断。只有当前整套内核、模块、DTB
组合完成了板上验收，不能把单个补丁抽出后宣称同样通过。

验证覆盖短响应/长响应排空、命令模式下寄存器回读、无效请求恢复、panel/DRM
卸载重载、VOP 预扫描寄存器与整机重启。详情见
[显示验证索引](../../app/slint-dashboard/validation/README.md)。

所有显示补丁已通过 checkpatch 严格检查，但尚未提交上游。0010 的按需读回会
跳过少量视频帧，是当前手动视频时序下的保守处理；为通用硬件上游化时，仍需
讨论完整 BTA 时隙配置、并发和其他面板适用性。0006 是标准 debug 输出扩展，
不要把 DMA 地址作为稳定用户态 ABI。

更新流程：在 `external/linux` 提交变更，运行 `scripts/export-patches.sh linux`，
再检查导出结果、构建、schema 和板上验证。导出会重新生成补丁编号/邮件头；
只要原始提交内容不变，0001—0004 的序列总数变化不代表串口行为发生改变。
