# Fork 内核崩溃信号失效 — WDT 伪影 (决定性发现)

> Timestamp: 2026-08-10 02:0x
> 来源: workflow w677jfvcr (2 sonnet agents, 86k tokens)。代码级验证。

## 核心发现: 900e 信号无效

- fork CONFIG_QCOM_WDT=m (模块), 但 boot initramfs (r11s_ubuntu_initramfs_20260731_2302)
  含 **零 .ko 文件**, init.src **无 modprobe/insmod/depmod**。
- => 每次 fork 内核启动, APSS WDT 从未被 pet -> ~60s 咬 -> warm reset -> 900e,
  **崩溃内核与健康内核产生相同结果**。60s 900e 无法区分崩溃 vs 健康 vs 挂起。
- boot-debug 4.19 未混淆: CONFIG_QCOM_WATCHDOG_V2=y (内建), 会 pet WDT。

## 已排除 (代码证据)

- EFI stub: head.S:61-62 efi_signature_nop + b primary_entry; 非 UEFI loader 跳 offset 0
  走正常入口, 不碰 PE entry。R11T 同路径启动。
- text_offset: R11T 7.0.14 text_offset 0 启动; head.S __HEAD 硬编码 .quad 0。
- KASLR: 无 kaslr-seed (boot-debug DT 验证) -> inert。
- VA_BITS 48/4K, PTR_AUTH, BTI, KPTI: R11T 同 config 族启动。
- size-0 memory: ABL 重写 /memory; boot-debug 的 DT 也是 <0 0 0 0> 且启动。
- 高 f6000000/ff700000 预留: fork-only, over-reserve 是安全方向。

## 存活嫌疑

1. **WDT 测量伪影 (高, 已验证)**: 900e 不证明崩溃。最高价值先杀掉。
2. **22M tz 间隙 (中)**: fork DTB memory@86200000 至 0x89500000; 固件 reserved 至 0x8ab00000。
   唯一 fork-vs-bootdebug 不安全方向的 DT 差异。E1/E3 隔离。
3. fork 内核 pre-initramfs 故障 (低-中): 目前与 (1) 不可区分。

## 决定性实验

- **E1 (已打包 a987d65f, 无构建)**: boot-debug 内核×fork DTB, 未混淆。现在就跑。
- **crashvar_wdton**: fork 内核 + CONFIG_QCOM_WDT=y (内建) + pstore。让 60s 信号有效,
  真崩溃时 ramoops 给出位置。
  - 持续 18d1:4ee7 无 900e -> 之前 900e 纯 WDT 伪影 -> fork 内核+DTB 健康 -> 可推进 Ubuntu
  - 900e + pstore 有记录 -> 真崩溃, pstore 定位 -> 再用 E3/E2 (现未混淆)
  - 900e 无 pstore -> 崩溃早于 ramoops init -> E3 (tz 0x4900000)
- E2/E3 (fork Image, QCOM_WDT=m) 有 WDT 混淆 -> 需在 wdton 构建后再跑。

## 构建 (crashvar_wdton)

O=/home/<user>/claude/r11/build/crashvar_wdton (独立 O=, 不污染共享树)
cp build/.config -> O/.config; scripts/config --file O/.config -e CONFIG_QCOM_WDT
make O=O ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig Image dtbs
打包: r11s_bootimg_pack.py --kernel O/Image --dtb O/.../sdm660-oppo-r11s.dtb
      --ramdisk r11s_ubuntu_initramfs.cpio.gz --cmdline '... loglevel=8 log_buf_len=1M'
