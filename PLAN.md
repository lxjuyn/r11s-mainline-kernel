# R11s 主线 Linux 计划与阶段门禁

> 本计划以 `R11S_MAINLINE_UBUNTU_GUIDE.md` 和 `CLAUDE.md` 为准。所有阶段均需保留证据文件与时间戳记录。

## P0 — 只读取证与回滚门禁

> 调研审计已完成，详见 `recon/FINAL_RESEARCH_REPORT.md`。下列仍是设备/原厂证据门禁，尚未执行。

- [ ] 核实精确型号、SoC、固件版本、bootloader 状态。
- [ ] 保存只读 fastboot 信息和 USB 枚举信息。
- [ ] 获取并 hash 原厂 boot/recovery/dtbo（若有）/分区表/恢复材料。
- [ ] 解析原厂 boot image，记录 header、page size、kernel、ramdisk、DTB/DTBO、cmdline 和签名关联。
- [ ] 判定 `fastboot boot` 是否支持；没有实测证据前不得假设支持。
- [ ] 记录 9008 为原厂恢复-only，且不用于自定义刷写。

**P0 退出门禁：**完整原厂回滚材料 + hash；明确 bootloader 状态；明确能使用的非破坏启动/恢复路径。

## P1 — 不上板主线参考构建

- [ ] 建立近期 upstream Linux tree（以后执行）。
- [ ] 用 arm64 工具链编译 SDM660 上游参考 DTB。
- [ ] 记录完整 config、compiler、commit、DTB hash。
- [ ] 建立 SDM660 SoC node 与 R11s board node 的证据矩阵。

**P1 退出门禁：**主机侧上游构建可复现；无任何 R11s 未取证节点进入 DTS。

## P2 — R11s 最小 DTS 证据包

- [ ] 下游 R11s DTS/DTB/DTBO 取证与解码。
- [ ] 核对 reserved-memory、PMIC/regulator、eMMC、pinctrl、USB DWC3/PHY、USB role。
- [ ] 制作最小 DTS；所有节点附来源行号/镜像偏移/硬件证据。
- [ ] 配置 ramoops/pstore 的前置条件；不得猜测内存地址。

**P2 退出门禁：**最小 DTS 仅包括有证据的启动必需节点；通过 dtc 静态检查与独立 review。

## P3 — USB-first 临时启动设计（需单独批准）

- [ ] DWC3 peripheral、PHY、regulator、UDC 的取证与配置。
- [ ] 先验证 CDC ACM gadget，后验证 ECM/NCM；记录 PC 端识别证据。
- [ ] 设计 initramfs 的最小 Ubuntu shell 与日志导出，不做完整桌面。
- [ ] 展示镜像打包参数、目标分区、原厂回滚路径，取得用户当次明确确认。

**P3 退出门禁：**只在用户明确批准且可回滚时开始实际设备测试。

## P4 — 分项外设 bring-up

按顺序拆分：eMMC → USB → regulator/battery → display → touch → Wi-Fi/BT → audio → modem → camera/suspend。每项均遵循 discover → fix → verify → archive。
