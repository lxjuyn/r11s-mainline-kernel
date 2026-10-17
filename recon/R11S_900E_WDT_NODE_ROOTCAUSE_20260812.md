# R11s 900e 根因: 缺 watchdog 节点 (决定性, 高置信)

> Timestamp: 2026-08-12 00:5x
> 来源: wf-wrknvazwb (config/DTS diff) + wf-wmq6z42wh (wdton 构建) + 本地验证。
> 配套: recon/FORK_WDT_ARTIFACT_20260810.md, recon/UBOOT_HANG_ROOTCAUSE_20260810.md

## 根因

**R11s bootloader (XBL/UEFI) 武装 boot 窗口 WDT (APSS @0x17817000), 但主线程 sdm660
DTS 无 watchdog 节点 -> qcom-wdt.c 匹配不到 (只认 qcom,kpss-wdt / apss-wdt / kpss-timer)
-> WDT 从未被喂 -> ~60s 咬 -> 900e, 即使是健康内核。**

sdm630.dtsi 只有 apcs-hmss-global mailbox @0x17911000 (匹配 "kpss" 但不是 watchdog)。

## 解释全部观察

| 内核/DTB | R11s 结果 | 原因 |
|---|---|---|
| boot-debug 4.19 (bootdebug.dtb 有 qcom,wdt@17817000) | ✅ 启动 | WDT 被喂 |
| fork 7.0 (faf80fa4, 无节点) | ❌ 60s 900e | WDT 未被喂 |
| crashvar_wdton (WDT=y 但 DTB 无节点) | ❌ 60s 900e | 驱动绑不上 |
| R11T Arch 7.0.9 (R11s DTB 无节点) | ❌ 60s 900e | WDT 未被喂 |
| R11T Arch 7.0.9 (R11T 自己) | ✅ 启动 Arch | **R11T bootloader 不武装 WDT** |

=> 900e 是 WDT 伪影 (内核可能健康, 被 60s WDT 杀), 与内核源码/配置/大小无关。

## 修复 (已实施)

fork DTS 加:
```
&soc {
	watchdog@17817000 {
		compatible = "qcom,kpss-timer";   /* legacy 0x38 偏移, match_data_apcs_tmr */
		reg = <0x0 0x17817000 0x0 0x1000>;
		interrupts = <0 3 1>;
		clocks = <&sleep_clk>;
	};
};
```
+ CONFIG_QCOM_WDT=y (crashvar_wdton 内核已有)。
证据: boot-debug dmesg "msm_watchdog 17817000.qcom,wdt: MSM Watchdog Initialized";
qcom-wdt.c match_data_apcs_tmr WDT_RST@0x38/WDT_EN@0x40 适合 sdm660。

## 验证镜像

- **crashvar_wdton2_boot.img SHA 704e264f** (13MB): fork 内核 QCOM_WDT=y + 新 DTB 9b7d0a10
  (含 watchdog@17817000) + pstore initramfs。归档 products_crashvar_wdton2_20260812_0040/
- 预期: qcom-wdt 绑定喂狗 -> 无 60s 900e -> 内核到达 initramfs -> USB ACM gadget/救援 shell
- 备选: r11t_wdton (精简内核, 需用新 DTB 重打包)

## 下一步 (门禁, 待用户确认)

刷 crashvar_wdton2 (704e264f) 验证。设备已恢复 fastboot。
若成功: 900e 纯 WDT 伪影确认, 内核健康 -> 推进 Ubuntu/rootfs (root=/dev/mmcblk0p69)。

## 2026-08-12 01:0x 双 workflow 高置信确认 (wf-wpeauwlwu)

- H1 HIGH: R11s boot 链 (ABL/XBL) 武装 boot 窗口 APSS WDT, 必须由 HLOS 持续喂;
  三个 7.0 组合都无法喂 (缺 DT 节点) -> 60s 900e 与内核健康无关。
- 唯一能启动的组合 (boot-debug 4.19) 兼具 DT watchdog 节点 + 匹配内建驱动。
- **修正**: crashvar_wdton 的 900e 是**假阴性** (QCOM_WDT=y 但 DTB 无节点, qcom-wdt.c
  是 platform driver 无节点不 probe) -> 不推翻 WDT 理论, 反而支持。
- **直接佐证**: r11s_uboot_debug_dt_boot.img (带 watchdog 节点) 撑 80s 无 900e。
- E1 有混淆 (boot-debug 内核需 qcom,msm-watchdog 兼容, fork DTB 无节点) -> 不优先。
- **决定性测试** = crashvar_wdton2 (704e264f): fork 内核 WDT=y + watchdog@17817000 节点。
