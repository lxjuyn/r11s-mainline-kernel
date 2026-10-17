# Fork 内核 pre-earlycon 崩溃 — 决定性实验集 (取证记录)

> Timestamp: 2026-08-10 01:0x
> 来源: workflow wtn27mig7 (4 agents, 255k tokens; 1 agent 流错误, 结论不受影响)。
> 配套: recon/R11S_ABL_BOOT_STATE_MACHINE_20260810.md, recon/FORK_DTS_AUDIT_20260810.md

## 综合结论

1. **text_offset 嫌疑被推翻 (H3 closed)**: fork Image code0 = efi_signature_nop + 有效 b primary_entry,
   entry@0x80080000 结构有效; ABL 对 gzip 不加 text_offset; **R11T (7.0.14, text_offset=0) 同款 ABL 家族能启动**。
   且 text_offset 不可配置 (head.S __HEAD 硬编码 .quad 0, 无 Makefile 行)。
2. **崩溃窗口 = pre-initramfs** (宽于 pre-earlycon): CONFIG_QCOM_WDT=m (模块), fork 内核在 initramfs
   加载模块前无法 pet WDT -> 60s 900e 意味着崩溃发生在 initramfs 之前任意点。
3. **22M tz_mem 间隙 (真实缺陷, 低先验)**: fork DTB tz_mem = 0x86200000+0x3300000 (51M, 至 0x89500000),
   实机/boot-debug 预留至 0x8ab00000 (73M)。间隙 0x89500000-0x8ab00000 可能被内核分配进固件内存。
4. ramoops@a0000000 干净无冲突。VA_BITS 48 vs 39 不相关。

排序: H1 (moderate) fork 内核 pre-initramfs 故障 (未定位) > H2 (low-moderate) fork DTB 结构错误 (22M 间隙) > H3 (closed) text_offset。

## 决定性实验集 (全部门禁 fastboot flash boot; 回滚 = boot-debug.img 4ff811c3)

| 实验 | 内容 | 判定 |
|---|---|---|
| **E1 TOP** | boot-debug 4.19 内核 × fork DTB (无需构建) | 启动 -> fork DTB 可启动 -> H1; 900e -> fork DTB 坏 -> H2 |
| E2 | fork 内核 × boot-debug DTB | 启动 -> fork DTB 坏; 900e -> fork 内核连 known-good DT 都崩 -> H1 |
| E3 | DTB-only: &tz_mem { reg = <0 0x86200000 0 0x4900000>; } (73M) | 单独解决 -> H2 确认 |
| E4 | 精简内核 e51a134d (已打包), 建议加 CONFIG_QCOM_WDT=y | 启动 -> 配置驱动 -> config bisect |
| E5 | splash-framebuffer 阶段标记 + ramoops 读回 | 找到崩溃阶段 (最费时) |

## 产物

- E1 已打包: products_crashiso_E1_revswap_20260810_0100/crashiso_E1_revswap.img
  SHA a987d65f..., 19.5MB (boot-debug kernel.bin + fork DTB + pstore initramfs)
- E4 已打包: products_r11s_smallkernel_test_20260809_231500 (e51a134d)
- bd_extract/: kernel.bin (4.19), kernel.bin.gz, bootdebug.dtb, bootdebug.dts.txt

## 下一步

E1 是最高价值下次刷写 (无构建, 30 分钟)。等用户确认后刷 E1 判定 H1 vs H2。
