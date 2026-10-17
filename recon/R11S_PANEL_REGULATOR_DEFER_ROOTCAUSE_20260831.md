# R11s v12 面板 regulator defer 根因调查 — 修正版（2026-08-31 第二轮）

调查对象：v12 实机日志（1.txt）中
`[11.750011] mipi-dsi c994000.dsi.0: deferred probe pending: panel-samsung-sofeg01-s: Failed to get regulators`

本文件为**修正版**：第一轮报告（同日早些时候）推测"RPM glink 整链未打开"为根因。
第二轮静态取证推翻了该假设。此处只保留经交叉验证的结论。

---

## 一、【推翻】RPM glink 整链死亡假设

第一轮假设：`rpm_requests` 通道未打开 → PM660/PM660L RPM regulators 未注册 → 面板 defer。

**反证（1.txt + v6 实测日志交叉）**：

1. 1.txt 中 `mipi-dsi c994000.dsi.0` 设备**存在**（deferred probe pending 消息的设备名就是它）
   ——面板 mipi-dsi 设备是 DSI host `mipi_dsi_host_register()` 创建的，
   而 DSI host 只有在 `dsi_dev_probe()` 完全成功后才注册。
2. `dsi_dev_probe()` → `msm_dsi_host_init()` 会 `devm_regulator_bulk_get(vdda)`，
   vdda = PM660 l1（`rpm-requests/regulators-1/l1`，phandle 0x5c）；
   `dsi_get_phy()` 要求 PHY 已 probe，而 PHY probe 需要 `vcca` =
   PM660L l1（`regulators-0/l1`，phandle 0x44）。
3. → **DSI.0 设备存在 ⟹ PM660 和 PM660L 两套 RPM regulators 组都已成功注册 ⟹ RPM glink 链是活的。**
4. 旁证：v6 实测（products_r11s_phase3_touch_v6_flash）regulator dump 显示
   `c994000.dsi.0-vddio`（l11）、`c994000.dsi.0-vdd`（l6）、`c994000.dsi.0-oledb`
   三条面板供电**全部解析成功**，显示打通（用户亲眼确认企鹅）。

结论：**RPM 链工作正常。v6→v12 之间面板 probe 从成功变为 defer 是一次回归。**

## 二、已证实：v6 与 v12 的 DTB 面板相关内容完全一致

dtc 反编译逐节点对比（v6 `appended_r11s_display_touch.dtb` vs v12 `dtb_v12.dtb`）：

- panel@0 节点（compatible/vddio/vdd/oledb phandle/reset-gpios/pinctrl）**逐字节一致**：
  vddio=0x5f→`rpm-requests/regulators-1/l11`（PM660L l11, 1.8V）
  vdd=0x60→`rpm-requests/regulators-0/l6`（PM660 l6, 3.0V）
  oledb=0x61→`spmi@800f000/pmic@3/oledb@e000`
- pmic@3（含 oledb@e000）整个 SPMI 子树**一致**（除下述 battery@4000）。
- mdss pinctrl 状态（0x62–0x65）一致。
- 完整 diff（排除空行）仅 4 处：
  1. `pmic@0/battery@4000`：status disabled → **okay**（v9 集成引入）
  2. `panel@1`（ams596w401，disabled）新增（v9 引入，v12 已 disabled）
  3. `pinctrl@15070000` 增加 `#pinctrl-cells = <1>`（v11 音频候选引入）
  4. `remoteproc adsp` firmware-name 加 `qcom/sdm660/` 前缀

## 三、已证实：v6 与 v12 的 config 关键差异 = 大量 =m → =y 翻转

v6 config（r11s_phase6.config）vs v12 config（config_v12）共 182 行差异，
除 AMS596W401（新增 =y，v6 无此驱动）外全部是 =m → =y，分四组：
- 音频链（SND/SND_SOC/QDSP6/SDM660_INT/AK4375/MAX98927/TFA989X…）
- 无线（BT/ATH10K/QRTR…）
- 电池/充电（BATTERY_PMI8998_FG/CHARGER_QCOM_SMB2/BQ27XXX…）
- SPMI 传感器（RRADC/ADC5/TEMP_ALARM）、LPASS_LPI pinctrl、Q6V5 remoteproc 等

**所有新增 =y 驱动的注册等级都是 `module_platform_driver` → 内建时为 `device_initcall`。**

## 四、核心嫌疑（按证据强度排序，待 v13 实测分辨）

### 嫌疑 A（最强）：device_initcall 段内 probe 顺序重排 + 一次性竞态

机制：`qcom_smd_rpm_init()`（arch_initcall）→ RPM 通道打开后
`qcom_smd_rpm_probe()` → `of_platform_populate(rpm-requests)` →
rpmcc/rpmpd/regulators-0/regulators-1 平台设备入队。
`rpm_reg_driver`（subsys_initcall 注册，PROBE_PREFER_ASYNCHRONOUS）probe 这些设备。

v6：面板驱动 probe（device_initcall 段，唯一 mipi-dsi 消费者）时，
RPM regulators 大概率已注册完成（v6 实测 6.5s OLEDB enabled + 面板成功）。

v12：device_initcall 段新增了几十个 =y 驱动（音频/无线/电池/充电/iio）。
内核 initcall 段内的**链接顺序**（Makefile 目标顺序）决定同段驱动注册顺序。
新增驱动改变：
1. sofeg01 驱动的相对注册位置；
2. **probe 的并发负载**（PROBE_PREFER_ASYNCHRONOUS 的 regulators probe 与
   其他 async probe 竞争 CPU/工作队列）；
3. 10s deferred_probe_timeout 窗口内 RPM 侧响应所需时间不变，但
   面板 probe 落点相对 regulators 注册完成的时序被重排。

若面板 probe 抢在 `regulators-1`（PM660L）probe 完成前 → -EPROBE_DEFER →
10s 超时后仍等不到（1.txt 11.75s 打印 = late_initcall + 10s 超时触发，
说明超时前**没有任何后续事件再触发 deferred probe 轮**）。

关键细节：`deferred_probe_timeout_work_func()` 触发时会
`driver_deferred_probe_trigger()` **再跑一轮** deferred probe 并打印仍挂起者。
若 regulators 在超时前最后一刻注册，这一轮本应让面板成功——除非
 regulators 在 11.75s 仍未注册，或最后一轮 probe 又被别的东西挡住。

**v6 成功 / v12 失败但 DTB 一致 ⟹ 最简解释 = 时序回归**。

### 嫌疑 B：qcom_spmi-regulator（=y，v6 也有）与 oledb 的 SPMI probe 竞争

`pmic@3/regulators {}` 空节点（compatible `qcom,pm660l-regulators`）会被
`qcom_spmi_regulator` 驱动（PROBE_PREFER_ASYNCHRONOUS）probe；
遍历内置 vreg 表全部注册（of_node 未匹配 → init_data=NULL 路径，无 DT 节点绑定）。
该驱动 v6/v12 均 =y，**不是 v6→v12 的新变量**，但其 async probe 与
oledb（同 pmic@3 下的 platform 设备）的相对顺序在 v12 的更大 initcall
负载下可能改变。oledb probe 若在 SPMI pmic populate 完成前运行会 defer，
之后由 deferred probe 轮补上——仍收敛于"超时窗口内最后一轮是否跑到"。

### 嫌疑 C（已基本排除）：battery@4000 → okay + smb2/fg =y 的依赖链

`battery@4000`（pmi8998-fg =y 新消费者）依赖 `power-supplies = <charger@1000>`
（smbx =y），smbx 依赖 rradc io-channels（=y）。这条链全部在 pmic@0，
与面板供电无 phandle 交集；即使 smb2 defer 也只影响自身。
fw_devlink 只按 DT 供应关系建 supplier/consumer 边，面板的 supplier
（l11/l6/oledb）不在该链上。**排除为根因，但它是 v12 新增 defer 项之一
（1.txt 未显示 = 它没挂起或日志截断）。**

## 五、v13 regdiag 镜像的判定价值（不变，且更关键）

v13 在两个面板驱动 bulk get 失败路径上加了逐条 `regulator_get()` 重试 +
`dev_warn` 各自 errno。刷入后 `dmesg | grep supply` 直接分辨：

- **三条全 -517**：所有 provider 都没注册成功（regulators/oledb 均未就绪）
  → 支持"RPM regulators 未在窗口内注册"（嫌疑 A 的极端形式）；
  同时看 `dmesg | grep -i "qcom_smd\|glink"` 和 `/sys/bus/rpmsg/devices/`。
- **vddio/vdd 成功(0)、仅 oledb -517**：RPM 组注册了但 oledb SPMI probe
  未完成（嫌疑 B）→ 查 `dmesg | grep oledb`、`/sys/bus/platform/devices/`。
- **某条 -19**：phandle 解析失败（静态不可能——DTB 已证一致，但防运行时意外）。

补充判据（救援 shell 内一键采集）：
```
dmesg | grep -iE "supply|oledb|glink|smd|rpm|deferred" > /tmp/diag.log
cat /sys/kernel/debug/devices_deferred
ls /sys/bus/rpmsg/devices/
cat /sys/kernel/debug/regulator/regulator_summary
```

## 六、若确认为时序回归的修复路径（下一步预案，不实施）

1. 面板驱动 probe 失败改为可重试且带诊断（v13 已做）；
2. 若是 RPM regulators 注册晚：给 `deferred_probe_timeout` 加 cmdline
   参数（如 `deferred_probe_timeout=30`）即可绕过一轮验证（最快验证手段，
   改 cmdline 重打包 v14）；
3. 根治（上游语义）：面板供电 defer 是正常机制，超时 10s 内未收敛说明
   RPM 注册链路在救援 ramdisk 环境下比 v6 慢（无 modules、异步负载大）。
   可考虑把 `qcom_smd_rpm_init` 提前或减少 device_initcall 段并发。

## 七、产物索引

- v13 regdiag 镜像：`out/boot_r11s_phase3_regdiag_v13.img`
  （sha256 0d2966a1…，15,106,048 B）
  归档：`backups/products/products_r11s_phase3_regdiag_v13_20260831_0211/`
- 源码提交：`419244cc3`（已推送 origin/main）
- 第一轮 web 研究（机制链验证仍有效）：`recon/v13_panel_web_research/`
  - web-rpm-defer.md：RPM glink → smd-rpm → regulators 依赖链（源码逐行）
  - web-sdm660-ecosystem.md：上游 SDM660 板 AMOLED 供电做法（regulator-fixed）
  - web-panel-autodetect.md：DCS ID 运行时变体选择先例（s6e8aa0）
- v6 实测日志（本修正的关键证据）：
  `backups/products/products_r11s_phase3_touch_v6_flash_20260829_205513/`
- v5 实测（OLEDB=m 是当时根因，v6 修复）：
  `backups/products/products_r11s_phase5_display_v5_flash_20260829_203207/`
