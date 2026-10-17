# LEDGER_dualpanel_20260901

> 配套报告：`recon/R11S_STATUS_DUALPANEL_GAP_20260901.md`
> 编排方式：`AGENT_ORCHESTRATION.md`（Hub-and-Spoke + Wave 调度）

## 任务表

| ID | 目标 | Wave | 状态 | 并发位 | 产物路径 | 证据 hash | 一句话结论 |
|----|------|------|------|--------|----------|-----------|-----------|
| A1 | 审计 sofeg01-s 驱动源码 | A | ✅ SUCCEEDED | 1/4 | `drivers/gpu/drm/panel/panel-samsung-sofeg01-s.c` | — | 504 行，compatible 唯一，1080×2160，背光 16-bit |
| A2 | 审计 ams596w401 驱动源码 | A | ✅ SUCCEEDED | 2/4 | `drivers/gpu/drm/panel/panel-samsung-ams596w401.c` | — | 554 行，1080×2280，供电/reset 与 A1 完全一致 |
| A3 | Kconfig/Makefile/defconfig 状态 | A | ✅ SUCCEEDED | 3/4 | `r11s_defconfig`、`build/r11s_phase2/.config` | — | 两符号均 =y，均编译为 built-in，无冲突 |
| A4 | DTS/DTB 面板节点取证 | A | ✅ SUCCEEDED | 4/4 | `dtb_v12.verify.dts:2333-2364` | — | panel@0 okay 有 port；panel@1 disabled **无 port** |
| L4 | 归档产物与回滚链盘点 | A | ⚠️ 由 Hub 兜底 | — | `backups/products/`（56 目录） | 见下 | 三个关键件 hash 全部复核通过 |
| B1 | 面板硬件身份 / driver IC | B | ⚠️ 未取证（L3） | — | — | — | 无有效公开资料，已降级 |
| B2 | 主线多面板自动探测先例 | B | ⚠️ 未取证（L3） | — | — | — | 搜索结果无有效证据，本地证据已足够定案 |
| B3 | RMI4 F12 描述符读失败 | B | ⚠️ 未取证（L3） | — | — | — | 仅得通用教程，无可操作结论 |
| B4 | SDM660 外设上游现状 | B | ✅ 部分成功 | — | `lwn.net/Articles/1058301` | — | SDM660 声卡补丁 v1(2026-02)→v4(2026-05) |
| C1 | sofeg01 家族跨机型佐证 | C | ❌ 未取证（L2→L3） | — | — | — | GitHub raw 超时，拆小重搜仍无内容 |
| C2 | SDM660 声卡补丁详情 | C | ✅ SUCCEEDED | — | LWN 1058301 | — | 10 补丁 → v4 扩至 15 补丁；合入状态未证实 |
| C3 | postmarketOS SDM660 状态 | C | ❌ 未取证（L2→L3） | — | — | — | Anubis 反爬拦截 |
| C4 | 主线多面板变体处理惯例 | C | ⚠️ 未取证 | — | — | — | 结果为通用 DT 教程，无参考价值 |
| D1 | 汇总产出报告 | D | ✅ SUCCEEDED | — | `recon/R11S_STATUS_DUALPANEL_GAP_20260901.md` | — | 9 项差距 G01–G09 |

## 已取证事实（去重后）

- **F01** 两个面板驱动均已内置内核：`panel-samsung-sofeg01-s.o`(311.76KB) / `panel-samsung-ams596w401.o`(312.47KB)，登记于 `build/r11s_phase2/modules.builtin:216-217`。来源 P1（本地构建产物）。
- **F02** 两者供电完全相同：`vddio`/`vdd`/`oledb`（`sofeg01-s.c:49-53`、`ams596w401.c:58-62`）。来源 P1。
- **F03** 两者共用 reset GPIO 53 与同一供电 phandle（0x5f/0x60/0x61）。来源 P2（原厂 DTB 反编译）`dtb_v12.verify.dts:2336-2342 / 2357-2363`。
- **F04** 选择机制为**编译期 DTB status**，非运行时探测：`panel@0` 无 status（=okay），`panel@1` `status="disabled"`。来源 P2 `:2333 / :2355`。
- **F05** 两驱动均**无变体 ID 探测**，仅 `mipi_dsi_dcs_read(0x0a)`（Get Power Mode）。来源 P1 `sofeg01-s.c:256`、`ams596w401.c:264`。
- **F06** `panel@1` 无 `port/endpoint`，`panel@0` 有。来源 P2 `:2344-2350` vs `:2353-2364`。
- **F07** 树内 R11s DTS 无任何显示节点，继承的 mdss/dsi0/dsi1 全 disabled。来源 P1 `.sdm660-oppo-r11s.dtb.dts.tmp:1630-1656 / 1732-1770 / 3045-3119`。
- **F08** 本机实为 SOFEG01_S（v13 实机 probe 成功，power mode 0x9e）。来源 P4（实机日志）。
- **F09** 固件清单缺 `qcom/a530_pm4.fw`；`adsp.mdt`(7964B)/`cdsp.mdt`(7068B)/`crbtfw21.tlv`(113976B) 在位。来源 P1。
- **F10** [联网·佐证级] SDM660 声卡上游补丁：v1 = 2026-02-10 / 10 补丁；v4 = 2026-05 / 15 补丁。合入状态未证实。
- **F11** 回滚链 hash 复核：`boot-debug.img` `4ff811c3…`、`v13.img` `0d2966a1…`、`rootfs_v3.ext4` `f54772b7…`，与 STATUS.md/HANDOFF.md 记载一致。来源 P1。

## 冲突（未仲裁 / 已仲裁）

| 编号 | 主张 A | 主张 B | 仲裁结果 | 依据 |
|---|---|---|---|---|
| K01 | 原厂 sofeg01_s 背光为 11-bit（`bl-max-level=0x3ff`）| 驱动实现为 16-bit DCS（max 1023） | **不冲突**：0x3ff=1023，两者数值一致，仅表述口径不同 | `r11s..dts:16306` vs `sofeg01-s.c:389-401` |
| K02 | 双面板"已兼容"（两驱动均 =y 且内置） | 双面板"未兼容"（无法自动识别） | **采纳 B**：内置 ≠ 兼容；选择仍是编译期开关 | F01 + F04 + F05 |

## 未取证（显式缺口）

| 编号 | 缺口 | 阻塞级别 | 补齐路径 |
|---|---|---|---|
| G-A | 面板 driver IC 精确型号（S6E3FCx 族？） | non-blocking | 原厂 dtsi 转录 / 实机 DSI 读 0xDA/0xDB |
| G-B | SDM660 声卡补丁是否已合入 7.0.14 | non-blocking（影响待办 #5 路线） | 树内 `grep -r sdm660-internal` |
| G-C | ams596w401 的 ESD `panel-status-value` | 🟡 中（= 差距 G06） | `android_kernel_oppo_sdm660_source_…/dsi-panel-oppo17011samsung_ams596w401_1080_2280_cmd.dtsi` |
| G-D | SDM660 主线 WiFi/GPU/modem 总体状态 | non-blocking | 实机验证优先于外部资料 |
| G-E | 主线同机型多面板变体处理惯例 | non-blocking | 本地证据已足够定案（F04/F05/F06） |

## 降级记录

| ID | 级别 | 原因 | 处置 | Hub 兜底 |
|----|------|------|------|----------|
| L4 | L3 | 子代理 `code=10003` abort（scope 过大） | Hub 亲自执行归档盘点 + hash 复核 | ✅ 是 |
| C1 | L2→L3 | GitHub raw 请求超时 10s | 拆小重搜 → 仍无正文 → 标记未取证 | ❌ 否（列 G-A） |
| C3 | L2→L3 | postmarketOS 被 Anubis 反爬拦截 | 改用搜索摘要替代页面抓取 → 无有效结果 → 标记未取证 | ❌ 否（列 G-D） |
| B1/B2/B3/C4 | L0/L3 | 搜索结果无有效证据 | 标记未取证，依赖本地一手证据定案 | ❌ 否 |
