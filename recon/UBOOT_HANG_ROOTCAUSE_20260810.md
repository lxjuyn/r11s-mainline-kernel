# U-Boot 卡 1 屏根因 — 定位并修复 (决定性)

> Timestamp: 2026-08-10 02:5x
> 来源: workflow wf4o5drjr (2 sonnet agents, 252k tokens)。代码级验证 + 修复构建。

## 根因 (HIGH 置信)

**UART2 时钟门从未使能 -> 首个 banner 打印时无限 -EAGAIN 自旋 -> 卡 1 屏。**

- `serial_msm.c` `msm_uart_clk_init` 只 `clk_get_by_name("core")` + `clk_set_rate`,
  **从不 `clk_enable`**。时钟门 GCC_BLSP1_UART2_APPS_CBCR / GCC_BLSP1_AHB_CBCR
  (clock-sdm660.c:157-158) 保持关闭。Oppo ABL 不会开 (R11s UART2 无物理引脚)。
- `serial-uclass.c:246-256` `_serial_putc` = `do { putc } while (err == -EAGAIN)`。
  无时钟 UART 读 SR=0 -> 永远 -EAGAIN -> 无限自旋在 `display_options` (board_f.c:923),
  任何字节输出前 -> "卡 1 屏, 无 host console"。
- Probe 本身成功 (set_rate 返回 1843200), cur_serial_dev 已设, 故自旋真实发生。

**次要 (MED-HIGH): XBL 武装的 ~60s 窗口 WDT 从未停止。**
- U-Boot 无 `qcom,kpss-wdt` 节点 -> initr_watchdog 空转 -> WDT 咬 -> warm reset -> 900e。

**低 (LOW-MED): PSCI SMC pre-console** (board.c qcom_psci_fixup)。

## 修复 (已实施 + 构建)

1. `serial_msm.c` msm_uart_clk_init: set_rate 后加 `clk_enable("core")` + `clk_enable("iface")`。
2. DTS 加 `watchdog@17817000 { compatible="qcom,kpss-wdt"; ... }` + qcom-wdt.c probe 时钟容忍 ->
   qcom_wdt_stop 运行 (停止 WDT)。
3. ramoops 捕获: CONFIG_CONSOLE_RAMOOPS + CONFIG_CMD_PSTORE* + DTS ramoops@a0000000
   (0xa0000000/4MiB, console 2MiB+pmsg 2MiB)。env stdout 已含 ramoops。
- 源码备份: backups/source/serial_msm_20260810_0159.c.bak, sdm660-oppo-r11s_uboot_*.dts.bak,
  qcom-sdm660-phone_*.env.bak, u-boot_r11s_config_*.bak

## 调试镜像

- `out/r11s_uboot_debug_boot.img` SHA `f6d6b150eaa7074602a5bf0484a8fce5bd70092952cb899cdf35a961e1f8bda7`
  (1,601,536 B, payload 1,549,936 B, image_size 0x2c58c0 < gate PASS)

## 预期结果 (门禁刷写验证)

- 屏上出现 U-Boot 文本 (simplefb banner @0x9d400000, board_r) -> 修复生效, U-Boot 到达 board_r
- 屏仍只有 OPPO logo -> pre-board_r (PSCI 或其它), 需屏幕证据继续
- ~60s 无 900e (WDT 已停) -> 修复 #2 生效
- usbacm 仍 opt-in (serial_gadget bootmenu), 未强制默认 (避免 tethered 假挂起)

## 下一步

门禁: 刷 r11s_uboot_debug_boot.img (f6d6b150) 验证修复。判定: 屏上 U-Boot banner 出现。
