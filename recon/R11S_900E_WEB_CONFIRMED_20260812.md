# R11s 900e — Web 大规模研究确认 (决定性)

> Timestamp: 2026-08-12 01:2x
> 来源: workflow wag40bwxb (6 sonnet agents, 527k tokens, 234 tool uses, firecrawl MCP)
> 配套: recon/R11S_900E_WDT_NODE_ROOTCAUSE_20260812.md

## 机制确认 (Qualcomm 官方 Debug Guide 80-70023-12)

- HLOS 必须每 ~10s pet 非安全 HW WDT; 下游 sdm660 节点: pet-time 10000 / bark-time 11000。
- ~60s = XBL 在交接前武装的 boot-window BITE 时间; 无人喂 -> WDT 咬 -> PS_HOLD 低 ->
  warm reset -> PBL -> 900e/9008 QUSB_BULK。
- 下游 4.19 绑定 qcom,msm-watchdog@qcom,wdt@17817000 并喂狗 -> 启动。
- **主线程 sdm630/660.dtsi 无 watchdog 节点** (验证: 零匹配) -> qcom-wdt.c 从不绑定。

## 精确修复 (与 crashvar_wdton3 完全一致)

```
watchdog@17817000 {
    compatible = "qcom,kpss-wdt";        /* KPSS 布局 RST@0x4 EN@0x8 BARK@0x10 BITE@0x14 */
    reg = <0x17817000 0x1000>;
    clocks = <&sleep_clk>;               /* 必填 (devm_clk_get_enabled); sdm630.dtsi 已定义 */
    interrupts = <GIC_SPI 3 IRQ_TYPE_EDGE_RISING>;   /* optional; 只用 index 0 (bark) */
    timeout-sec = <30>;                  /* 默认已 30, 可省 */
};
```
- 不要用 qcom,kpss-timer (那是 apcs_tmr 布局 EN@0x40, 错) / qcom,apss-wdt-sdm660 (无驱动项)。
- 无驱动补丁 (stock qcom,kpss-wdt 即可); CONFIG_QCOM_WDT=y 内建。
- qcom-wdt.c: irq = platform_get_irq_optional(0) -> optional; timeout 默认 min(max,30)=30。

## 关键佐证

- U-Boot 驱动 (2025-04 上游化) 只匹配 qcom,kpss-wdt, 写 0 到 base+WDT_EN(0x8) 停 WDT;
  其在 sdm660@0x17817000 成功 => 硬件用 KPSS 布局 (EN@0x8), 与主线程兼容。
- 主线程 sdm630/660 无 qcom,kpss-timer 节点 -> 与 timer-qcom 无冲突。
- pmOS sdm660 设备 (lavender 等) 用 lk2nd 处理 XBL 交接, 主线程无节点方案; sdm845 是
  watchdog@17980000 + qcom,apss-wdt-sdm845/kpss-wdt 的先例。

## 验证镜像

- **crashvar_wdton3_boot.img SHA dd770eb7** (fork 内核 QCOM_WDT=y + watchdog@17817000
  qcom,kpss-wdt + pstore initramfs) — 与 web 精确修复一致, 可直接刷。
- 预期: qcom-wdt 绑定喂狗 -> 无 60s 900e -> 内核到 initramfs -> USB ACM 救援 shell。

## 下一步

用户确认后刷 dd770eb7 验证。成功 = 900e 纯 WDT 未被喂, 内核健康 -> 推进 Ubuntu/rootfs。
