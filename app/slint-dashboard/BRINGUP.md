# Slint 显示调试档案（2026-09-14—15）

> 本文件保存调试时的观察、实验和部署记录；当前使用方式见 [README](README.md)，验收状态见 [PLAN](PLAN.md)。
> 2026-09-15 晚间用户确认：“现在界面有ui”。实际接屏为 J23，Mali GPU 渲染。
> 出图时采用 CPLL / 375 MHz 的 DSI 系统时钟，已固化到设备树并通过重启验证。
> 自动测试中的 PASS 仍仅表示其声明的软件/硬件接口范围，实屏证据来自用户观察。

## 最终目标

在主线 Linux 7.2.5、现有 U-Boot、Ubuntu Base 26.04.1 上，以非 root 身份运行
Slint GPU 状态界面。屏幕为用户确认的 J23、5.5 寸、1080×1920 MIPI 屏。
正式程序固定 LinuxKMS + FemtoVG + OpenGL ES，拒绝 CPU 软件渲染实现。

## 实施步骤

1. 已完成：检查 SDK 接线、开发板运行状态、内核模块与启动配置。
2. 已完成：通过主线 SARADC/IIO 读取 ID 电阻，匹配 1080p；核对 J23 → DSI0/I²C5。
3. 已完成：新增 DRM panel 模块及 binding，接入主线 DSI2、PWM 背光、Goodix。
4. 已完成：启用 Mali GPU 和 GPU 电源域的真实供电，安装 Panthor 所需 CSF 固件及 Mesa。
5. 已完成：实现 Slint 状态界面、GPU 身份/帧/输入日志、GPU 回读截图。
6. 已完成：GBM 按主平面的 IN_FORMATS 协商 AFBC，固定 Cargo 依赖和本地后端补丁。
7. 已完成：交叉构建、非 root systemd 服务、依赖准备、部署、自动测试及回滚入口。
8. 已完成：主机检查、实机 GPU/扫描输出/事件注入，以及完整重启后的重复验证。
9. 已完成：原厂 Linux 5.10.160 + ARM libmali 基线、EoT 开关对照、主线修复与面板 DCS 自动检查。
10. 已完成局部验证：分别读回主线和原厂的 VOP 合成输出，均包含完整界面。
11. 已获得实屏确认：DSI 系统时钟切到 CPLL / 375 MHz 后，J23 正确显示 GPU UI。
12. 已完成：时钟配置固化、DCS 读回修复，重启后自动启动和完整 GPU/输入测试通过。

## 关键实现判断

- ID 电阻表来自原厂文档：ADC7 约 0 / 1410 / 2748 对应三类屏幕。
  实测稳定样本 1417–1421，与 5.5 寸 1080p 一致；后续采样也落在匹配容差内。
- J23 在原理图中叫 MIPI DSI1，Linux 控制器是 dsi0，DRM 输出是 DSI-1。
- 面板初始化来自 SDK 的 19 条命令和延时，按主线 DRM panel 生命周期组织。
  实机对照发现照搬 SDK 的禁用 EoT 行为会造成持续接收错误；最终保留主线默认 EoT。
- 像素时钟采用板上可准确输出的 118.8 MHz，保留原厂 porch/sync 参数。
- GPU 同时需要 gpu/mali-supply 和 pd_gpu/domain-supply；缺少后者会破坏电源域恢复。
- Ubuntu 提供压缩固件，而现有内核不支持其解压；准备脚本从官方软件包解压出标准
  路径下的 CSF firmware。正式运行使用 Panthor/Mesa；原厂 Mali 仅用于隔离的诊断启动。
- 初期软件渲染的行跨度问题已在诊断中发现；按最终 GPU 要求，该软件方案已退出。
  正式 GPU 路径按主平面公布的修饰符分配 AFBC，避免未协商的缓冲区布局。
- 实验阶段曾遇到面板卸载重复 DCS 访问及 GPU 电源缺失时的失败恢复异常。
  当前代码删除了卸载阶段的重复 DCS 调用，并补全电源域供电；正常重启后的测试中
  内核 taint 仅为树外模块的 4096，无新增 Oops/WARN/MACHINE_CHECK 标记。

## 自动设备检查（2026-09-14 至 2026-09-15，不含实屏点亮）

- 当前内核：7.2.5-atk-dlrk3588+；Panthor 1.8.0。
- GPU：Mali-G610 MC4 (Panfrost)，OpenGL ES 3.1，Mesa 26.0.8-1ubuntu0.3。
- CSF firmware：接口 v1.5.0，git sha 95a25d71030715381f33105394285e1dcc860a65。
- GPU firmware SHA-256：a27847ea11f8efb3136340c3ba8aab413ae25145eeb4a7f64ff5edd829a2405b。
- 输出：DSI-1，1080×1920；扫描缓冲区为 XRGB8888 / AFBC
  0x0800000000000051（16×16、YTR、SPARSE），pitch 4352 字节。
- 进程：专用 slint-display 用户，CapEff=0，通过 libseat/seatd 和 render 组访问设备。
- 初次自动测试：5 秒采样内 GPU 执行时间增长 6,793,792 ns。
- 最新正式部署重启后，boot ID 为 73928060-bd62-47cb-9d6a-175e21e276fc，
  内核构建版本为 #5，服务自动运行；5 秒内 GPU 执行时间增长 5,755,167 ns，GPU 回读得到
  非空 1080×1920 PNG，记录与保存图像的文件大小一致。
- Goodix evdev 注入测试：Reset → Count=1 → Pause → Resume → Reset=0 全部通过，
  `UI_ACTION` 日志与状态一致；测试结束已恢复计数 0、暂停 false。
- rustfmt、Clippy -D warnings、6 个应用测试、5 个启动项/ADC 测试通过；BSP 原有检查通过。
- 面板模块 W=1 和 checkpatch 严格检查通过；显示/GPU/电源/触摸相关 DT schema 检查无输出。

机器可读结果见 [validation/gpu-after-reboot.json](validation/gpu-after-reboot.json)，
GPU 回读图见 [validation/gpu-frame.png](validation/gpu-frame.png)。
这些记录证明 GPU 执行、渲染内容、扫描提交和输入事件链路；截图为 GPU 回读，
不是玻璃面板的照片；事件测试为内核 evdev 注入，不冒充人工触摸测试。

## 面板链路修复与原厂对照（2026-09-15）

原厂 Linux 5.10.160、Mali 内核 DDK g18p0、libmali g13p0 在现有 Ubuntu Base 上
成功运行同一 Slint 界面，GPU 身份为 ARM Mali-G610 / OpenGL ES 3.2。
原厂与主线 DSI 视频时序寄存器相同；两者在禁用 EoT 时均出现面板接收错误。
原厂基线上反复切换 EOTP_TX_EN：关闭后错误计数持续增长或溢出，开启并读取清除后
计数保持零，显示状态从 80730401 变为 80730400。因此修正面板 mode_flags，
启用默认 EoT；原厂 PHY 驱动强度无需引入正式主线配置。

面板 ID 为 83 99 0c，电源状态 9d、像素格式 77、自检 c0；当时扫描行读数持续变化。
状态判据参考 [Himax HX8399-C 数据手册](https://dl.espressif.com/AE/esp-iot-solution/HX8399-C_DS_temporary_v00.06_150714.pdf)。
RGB 通道读回在两套驱动下均为零，其采样位置与有效性仍待核实。
保留这些原始读数作为排查线索，不将零错误计数或扫描行推进当作有图像的证据。

新增按需 debugfs 诊断，无后台轮询。与关闭操作并发读取通过测试：关闭后返回
ENODEV，重新绑定后恢复读取，无新增内核异常。DSI2 响应修复也通过真实面板测试：
最大返回长度为 1 时，四字节请求正确返回 1；最大长度为 8 时，一字节读取之后的
四字节读取仍正确返回 80730400，验证剩余 RX 数据已排空。

纯色测试发现原截图时机处于 GBM 交换之后，可能读取上一帧；已移动到
AfterRendering 回调中，在本帧完成绘制、交换缓冲区之前读取。
修正后，重启实测五色 GPU 回读分别为黑、红、绿、蓝、白的正确 RGBA 值，
所有采样的面板状态均为 80730400，连续错误计数均为 0。
独立 `--capture` 模式也成功保存 GPU 图像并正常退出；最终已恢复常驻界面。

证据文件：[五色 GPU 与面板检查](validation/gpu-patterns.json)、
[面板关闭并发检查](validation/panel-lifecycle.json)、
[原厂 EoT 开关对照](validation/vendor-eotp-ab.txt)。

## 实屏观察能力核查（2026-09-15）

当前主机没有视频采集设备。开发板 video0–video4 分别属于 RGA、视频编码器和
解码器，没有暴露摄像采集接口；IIO 只有 SARADC，没有暴露测光传感器。
背光实际状态为开启，PWM 实际输出为 25000/25000 ns；GPU 服务持续运行，
面板 DCS 状态为 80730400、错误计数为零。核查记录见
[observation-audit.json](validation/observation-audit.json)。

这次核查只能说明远程观察手段的范围。用户随后明确反馈实屏仍然黑屏，
因此问题是尚未解决的显示故障，不能缩小为只缺光学验收。

## 点亮前的全链路复查（2026-09-15）

- 在独立的原厂 5.10.160 / ARM Mali 环境中，通过标准 DRM Writeback 接口捕获
  VP3 输出；在主线 7.2.5 / Panthor 环境中，使用同一硬件 Writeback 单元捕获。
  两者均包含 Slint 界面，证明图像已进入 VOP 合成输出。
- 捕获采用 1072×960：Writeback 横向按 16 像素组对齐，纵向缩小一半。
  这些是显示控制器读回，不是屏幕照片，见
  [主线 VOP 输出](validation/vop-mainline.png) 和 [原厂 VOP 输出](validation/vop-vendor.png)。
- 修复 DSI 模式等待误用位掩码：COMMAND_MODE=2 不能被 VIDEO_MODE=3 的等待条件接受。
- 修复 DSI2 下游面板桥接对象重复释放：使用 devres group 配对 attach/detach，
  避免手动删除后再执行 managed 删除；面板 remove 同时避免 host 已解绑后的重复 detach。
  复现过原崩溃；修复后两次面板重载及完整 rockchipdrm 卸载/重载通过，taint 保持 4096。
- 增加标准 GEM print_info 的 DMA 地址输出，用于区分 CPU 地址与显示 IOVA。
- 补回原厂 RK3588 的预扫描同步宽度最小 8 像素处理：本模式实际 HSync 为 6，
  主线此前写入 0x024f0006，原厂写入 0x024f0008；修正只作用于预扫描，不改传输时序。
- 60 Hz、C6、扫描方向、内部白场、亮度控制、LP 初始化和高速消隐均做过限定试验，
  没有把未证明有效的参数留作正式配置。高速消隐会阻塞部分读回，已通过重启清理。
- 面板显式 All Pixels On 命令能使状态由 80730400 变为 80731400，恢复 Normal 后
  回到 80730400；没有据此宣称玻璃实际变白。关闭外部视频后扫描行仍会推进，
  进一步说明扫描行不是实屏图像的充分证据。

该阶段检测工具输出 `visible_image_verified=false`，当时全功能目标尚未完成。
后续的时钟修复与实屏确认见下一节。
机器记录见 [comprehensive-audit.json](validation/comprehensive-audit.json)。

## 点亮修复与实屏确认（2026-09-15 晚间）

用户在时钟对照期间先报告短暂出现正确页面，随后确认“现在界面有ui”。
后一次反馈期间，系统稳定保持 CPLL / 375 MHz 的 DSI 系统时钟；Slint 仍使用
主线 Panthor、Mesa 与 Mali-G610 GPU，输出保持 VP3 → DSI0 → J23。
已在 J23 专用设备树中用标准 assigned-clocks/parents/rates 固化此配置。
面板像素时钟仍为 118.8 MHz，未修改正常工作的 U-Boot 或全局 PLL 频率。

故障定位到 DSI 系统时钟选择。SPLL 的软件报告值不能替代实际频率测量；
固件拒绝本次安全寄存器读请求，因此没有把“实际 SPLL 必定减半”写成实测结论。
[上游报告](https://lists.infradead.org/pipermail/linux-arm-kernel/2026-August/1163857.html)
提到 SPLL 初始化会导致 DSI 黑屏；本次正式修复是显式选择
CRU 管理的 CPLL，实屏成功证据来自本板用户的反馈。

长寄存器读回另有独立问题：视频模式下数据会发生位移或读取超时，暂停视频后，
电源、GIP 和 54 字节 Gamma 数据稳定返回初始化值。新增 DSI2 补丁将读取事务
限定在命令模式内，读完或出错后恢复视频。模式切换允许等待 100 ms，以覆盖
帧边界：原 10 ms 限制小于当前约 18.6 ms 帧周期，实测会误报超时。
错误请求返回 -EINVAL 后也恢复 mode=3；正常状态为 80730400、接收错误为零。
按需诊断可能跳过少量视频帧，正常 Slint 服务没有后台 DCS 轮询。

新增自动检查验证 CPLL / 375 MHz 和诊断后的 VIDEO_MODE。扫描行保留原始值，
不再要求两次读取必须不同，因为诊断可能两次都停在同一帧边界。输入注入间隔
调整为 700 ms，避免连续点击受 libinput 去抖影响；后续完整测试已通过。
证据见 [寄存器读回](validation/dsi-read-audit.txt) 和
[错误请求恢复](validation/dsi-read-error-recovery.txt)。

重启后核对到的 DTB SHA-256 为
`60da4fd6ca83050f1d1b6a925bd44962e9e13ec30d01cb5fa1bf1d5b4068c182`。
新 boot ID 为 `73928060-bd62-47cb-9d6a-175e21e276fc`，临时时钟模块未加载，
`clk_dsihost0` 的父时钟为 cpll、频率为 375000000 Hz。Slint PID 340 自动启动、
NRestarts=0；GPU 回读 PNG 为 1080×1920、101372 字节，五秒 GPU 执行时间增长
5755167 ns。输入注入、面板状态和 mode=3 恢复检查全部通过，taint 只有树外模块位，
新启动无 DSI 超时、WARN 或 Oops。结果见
[重启验证](validation/gpu-after-reboot.json) 与
[完整记录](validation/comprehensive-audit.json)。

## 部署与回滚

构建入口：make linux / display / package；显示安装：make deploy-display。
验证入口：make test-display DISPLAY_TEST_ARGS=--touch。
详细命令、依赖和日志说明见 [README.md](README.md)。

当前默认启动项为 bsp；原 rust 启动项及其 Image/DTB 保留。
旧根目录 Image 经 SHA-256 校验后存入 /var/backups/slint-boot-space.cwa1lon8/，
为 /boot 腾出空间；没有改动 U-Boot 或重刷分区。应用和内核安装均保留备份。
本轮替换 BSP Image 前，先将默认项切到已验证的 rust 回退项并校验备份，
新 Image 安装成功后恢复默认 bsp；旧 BSP Image/DTB/启动配置备份位于
/var/backups/slint-bsp-image.6eguypqn/。新 Image SHA-256 为
7f5b1e165c730e404725261c585426a2e3fe3a60c1950059cdf1bb8b7ef6fad8。

晚间正式部署备份位于 `/var/backups/atk-dlrk3588-bsp/20260915-205441`。
部署包 SHA-256 为 `6cc7729cec13f643de4ffdfa6f9caad82bf7b46bf30665a468a19d57d1c422df`。
Image 保持上述 SHA-256，更新了 J23 DTB 和 DSI2 内核模块；默认仍为 bsp。
