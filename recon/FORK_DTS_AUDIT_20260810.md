# Fork 内核 R11s DTS/config 审计 — 取证记录

> Timestamp: 2026-08-10 00:5x
> 来源: workflow wsap7i3h6 (2 sonnet agents, 150k tokens)。对照下游 r11s..dts 逐区审计。

## 结论: DTS/config 不阻塞 earlycon

崩溃在 pre-earlycon (head.S/pre-decompress), 早于 earlycon 读取的任何 DTS 内容 ->
**无 DTS 修复能成为 boot blocker**。

## 逐区审计表

| 区 | fork | 下游 | 风险 |
|---|---|---|---|
| memory | size=0 (sdm630.dtsi) | 6GB 映射 (4GB 设备) | LOW — R11T 同款 size=0 能启动, ABL 修复 |
| reserved-memory | adsp/mba/cdsp 已对齐 + ramoops@a0000000 | removed_regions 等 | LOW-MED — ramoops 在真空闲区, 无 TZ 冲突 |
| DWC3/USB | usb3@a8f8800 + qusb2phy0@c012000 | ssusb@a800000 | LOW — gadget 救援路径完好 |
| eMMC sdhc_1 | 无 hs400/hs200 帽 | HS400_1p8v | MED — 仅 3.3V HS, 不阻 USB console |
| PMIC rails | l1b/l10a/l7b | 精确匹配 | LOW |
| chosen/aliases | serial0 + stdout-path | 匹配 | None |
| config | VA=PA=48, 4K | — | Good |

## 修正与建议

- **CONFIG_SERIAL_MSM_EARLYCON 不存在于本树** (早期 agent 误报); msm_serial 无条件注册
  OF_EARLYCON_DECLARE, earlycon 已可用。无需改。
- **RANDOMIZE_BASE=y (KASLR)**: fork DTB 无 kaslr-seed。建议 chosen 加 `kaslr-seed=<0x0 0x0>`
  (下游 r11s..dts:17014 同款), 确定性早启调试。但会改 Image hash (非 byte-identical)。
- eMMC HS400/HS200 caps + rails: console/USB 证明后再说。
- memory size=0 保持 (勿复制下游 6GB reg, ABL skip fixup 时会映射不存在的 RAM)。

## 对崩溃诊断的含义

- DTS 不是根因; 崩溃在 pre-earlycon 内核最早期代码。
- 决定性变量是内核二进制 (text_offset=0 vs boot-debug 0x80000) / ABL 入口, 非 DTS。
- 下次测试镜像仍用归档验证 Image (37f611dd) + 已修 DTB + pstore initramfs;
  预期同崩溃, 除非 text_offset 实验 (wf-crash wtn27mig7 设计) 改变内核二进制。
