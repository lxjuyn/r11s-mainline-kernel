# R11s ABL 引导状态机 — 取证记录 (决定性)

> Timestamp: 2026-08-10 00:3x
> 来源: workflow w38345gxg (3 sonnet agents, 281k tokens)。从 QcomModulePkg BootLinux.c/LocateDeviceTree.c 源码 (R11s 时代结构) 逐字节验证。

## ABL 序列 (R11s 时代)

1. 读 boot v1 header; kernel 字段在 PageSize。
2. `KernelLoadAddr = BaseMemory | PcdGet32(0x80000)` = **0x80080000** (header kernel_addr 忽略;
   **text_offset 仅对非 gzip 加**, gzip 不加)。
3. 解压 kernel; 失败 -> fastboot。
4. 解压后 Image magic "ARM\x64" (否则按 32-bit)。
5. **尺寸门**: `Kptr->ImageSize > (DeviceTreeLoadAddr − KernelLoadAddr)` -> "DTB header can get corrupted" -> fastboot。窗口 [0x80080000,0x83200000) = 0x3180000。
6. **appended-DTB 门**: 从 `kernel+DtbOffset` 起扫 FDT 头。无 -> "DTB offset is incorrect" -> fastboot。
   `DtbOffset>=ImageSize` -> fastboot。每个 DTB 校验 qcom,msm-id/board-id/pmic-id 与芯片匹配,
   不匹配 -> fastboot。匹配 -> 复制 DTB 到 DeviceTreeLoadAddr, 清零 kernel 字段 FDT magic。
7. UpdateDeviceTree() 重写 /memory (RAM 分区表) + bootargs; ShutdownUefiBootServices();
   **jump**: LinuxKernel(DeviceTreeLoadAddr,...) 到 KernelLoadAddr (x0=FDT)。

## 三种结局的根因 (全部验证)

| 结局 | 根因 |
|---|---|
| (b) U-Boot 无 DTB -> **回 fastboot** | 门 5 过 (0x17a618<gate), 门 6 败 (kernel 字段内无 appended FDT) -> EFI_BAD_BUFFER_SIZE; ABL 驻留 -> fastboot |
| (c) U-Boot+DTB -> **卡 1 屏** | 门 6 过 (board-id 匹配), **ABL 已跳到 U-Boot@0x80080000**; 挂起在 U-Boot 内部: OF_SEPARATE 内嵌 lavender DT (忽略 x0), 外设不匹配 -> 卡在 CDC-ACM console 前; ABL 健康 |
| (a) fork 内核 -> **~60s 后下载模式** | 门 5/6 过, ABL 退出 UEFI 并跳转; fork 内核 (text_offset=0, MZ code0) **pre-earlycon/pre-ramoops 崩溃**; ABL 已走无 fastboot 回退; 固件 WDT ~60-70s 咬 -> warm reset WDOG_BITE -> PBL 视为 emergency-download -> 枚举 05c6:900e QUSB_BULK |

## 看门狗机制 (R3B)

- EDL/QDL 在 PBL (boot ROM), 不可被软件破坏; 下一级 XBL 加载失败/强制触发/reset 请求时进入。
- ~60s 窗口 = XBL/UEFI 在内核交接前武装的 boot-window WDT。fork 内核 pre-earlycon 崩溃,
  从未 pet APSS WDT (qcom-wdt) -> 到超时 WDT 咬 -> TZ 断 PS_HOLD -> PMIC 复位 -> warm reset ->
  XBL crash-dump/download 路径。
- pre-earlycon 崩溃不跑 panic 机制、不写 IMEM cookie -> 只留 bootloader WDT 未 pet -> bite-reset->download。
- 3 态: ① 卡1屏->QUSB_BULK(~60s)=ABL 跳了、载荷早期死、WDT 咬; ② 卡1屏 forever=载荷跑但 WDT 未武装/在 pet; ③ 回 fastboot=ABL 跳前拒绝。

## 对当前工作的含义

1. **U-Boot 合同已验证**: ABL 接受我们 appended-DTB 载荷并跳转。挂起是 **U-Boot 在 lavender DT 上卡住**
   (内存/UART/外设不匹配) -> 需要 **R11s 板 DTS (④)**。预构建隔离测试预期同样挂 -> 不必刷。
2. **fork 内核崩溃**: 真在 pre-earlycon (MZ code0 / text_offset=0 可疑), ABL 健康; 下载模式是 WDT 咬。
   boot-debug (text_offset=0x80000) 能启动 vs fork (text_offset=0) 崩溃 -> **text_offset 是头号嫌疑**。
   决定性实验: 把 fork 构建为 text_offset=0x80000 再测 (wf-crash 设计)。
