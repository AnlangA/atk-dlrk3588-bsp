# 显示验证数据索引

当前结论见 [PLAN](../PLAN.md)。本目录同时保存最终验收和历史实验，文件中的
旧状态描述是当时的观察；不能将历史 `goal_complete=false` 解释为当前仍未点亮。

## 当前验收与复核

| 文件 | 来源与范围 |
| --- | --- |
| [gpu-after-reboot.json](gpu-after-reboot.json) | 2026-09-15 正式部署重启后的 GPU、AFBC、截图、DCS、时钟和输入注入 |
| [gpu-frame.png](gpu-frame.png) | 上述测试的 1080×1920 GPU 回读；不是玻璃面板照片 |
| [comprehensive-audit.json](comprehensive-audit.json) | 汇总：用户实屏确认、正式修复、重启结果、限制和备份 |
| [release-manifest.json](release-manifest.json) | 版本、部署产物/固件/源文件校验值和整理时的只读设备复核 |
| [maintenance-check.json](maintenance-check.json) | 整理后的宿主机检查、Slint 原包+补丁一致性和暂停状态测试 |
| [maintenance-gpu-frame.png](maintenance-gpu-frame.png) | 维护测试在 Pause 状态请求的 GPU 截图；测试结束后已恢复 Live |

`gpu-after-reboot.json` 的 `visible_image_verified=false` 表示自动测试自身没有测量
玻璃图像；`comprehensive-audit.json` 的 `visual_output_verified=true` 来自用户
明确观察到 J23 正确 UI。两者的数据来源不同，不矛盾。

## 故障修复证据

| 文件 | 验证内容 | 不能证明的内容 |
| --- | --- | --- |
| [dsi-read-audit.txt](dsi-read-audit.txt) | 命令模式内，power/GIP/Gamma 等读回；保留 B2 差异与 C1 查询占位说明 | 不把所有 expected 字段都当成先前写入值 |
| [dsi-read-error-recovery.txt](dsi-read-error-recovery.txt) | 无效请求返回 -EINVAL，DSI 恢复 VIDEO_MODE=3 | 不是所有硬件故障/超时组合的穷尽测试 |
| [bridge-lifetime-reload.txt](bridge-lifetime-reload.txt) | panel 与完整 DRM 卸载/重载，无新增 WARN/Oops | 不代表任意热插拔或所有并发情形均验证 |
| [panel-lifecycle.json](panel-lifecycle.json) | 并发诊断/关闭，关闭期间返回 ENODEV | 不证明玻璃点亮 |
| [gpu-patterns.json](gpu-patterns.json) | 黑红绿蓝白的 GPU 像素回读正确，验证截图时机 | 不是实屏色彩校准 |
| [vendor-eotp-ab.txt](vendor-eotp-ab.txt) | 原厂栈 EoT 开关与面板接收错误的因果对照 | EoT 修正自身没有完成点亮 |
| [vop-mainline.png](vop-mainline.png) | 主线 GPU 输出经 VOP 硬件 Writeback 读回，1072×960 | 不覆盖 DSI 线缆和玻璃 |
| [vop-vendor.png](vop-vendor.png) | 原厂 Linux/ARM Mali 输出经 VOP Writeback 读回 | 原厂栈只是隔离诊断基线 |
| [observation-audit.json](observation-audit.json) | 点亮前，核查摄像头/测光通道可用性 | 后续用户确认 UI 后，不再以缺少摄像头作为完成障碍 |

## 校验和保存规则

在本目录执行 `sha256sum -c SHA256SUMS` 验证证据文件。清单不包含自身。
文件可能包含 boot ID、PID、版本和时间，但不保存密码、SSH 私钥、sudo stdin 或
整个 `local.env`。主机绝对路径只出现在必要的来源记录中。

`build/panel-bringup/` 保存更完整的构建/串口/实验日志；`local/slint/` 保存未作为
正式工具交付的诊断程序。两者被 Git 忽略，不是重新构建正式功能的前置条件。
源码、Cargo.lock、已修改的后端 crate、补丁、配置与本目录精选证据是交付内容。

历史证据不随新测试覆盖。新增验证应另存记录，再更新索引和 SHA256SUMS。
GPU 截图包含运行时间等可变数据，后续截图的哈希不同是正常现象。
