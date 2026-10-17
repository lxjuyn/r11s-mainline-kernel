# R11s eMMC Partition Layout — 取证记录

> Timestamp: 2026-08-09
> 来源: workflow wxaa4ha4q (1 sonnet agent, 23 tool uses)。数据一手来源 = 本地 OTA 镜像 + 实机只读 dump。

## 摘要

- 设备: Oppo R11s (17011, SDM660/arm64), **经典单槽** (无 A/B), 69 个 GPT 分区 p1–p69, 无空隙。
- 关键分区: boot=p21, bootbak=p22, recovery=p23, dsp=p34, xbl=p10, tz=p12, rpm=p14, hyp=p16, pmic=p18, modem=p64, cache=p65, system=p66, vendor=p67, userdata=p69, vbmeta=p62。
- **无 dtb/dtbo 分区** —— boot 是单一镜像。

## 来源 A — OTA updater-script (37 分区并集)

`R11s_11_OTA_1170.zip` 的 `META-INF/com/google/android/updater-script`: system+vendor 走 `block_image_update` (system.new.dat.br), `boot.img`→by-name/boot, 固件走 `package_extract_file`。
C.19 底包: 写 boot.img→boot 和 vendor.img→vendor (1GB vendor.img)。

全部分区 (by-name, 去重并集):
`abl ablbak apdp bluetooth boot cmnlib cmnlib64 cmnlib64bak cmnlibbak devcfg devcfgbak DRIVER dsp hyp hypbak keymaster keymasterbak LOGO mdtp mdtpbak mdtpsecapp mdtpsecappbak modem msadp oppostanvbk pmic pmicbak rpm rpmbak splash storsec system tz tzbak vendor xbl xblbak`

## 来源 B — 实机只读 GPT (p0_adb_readonly_20260730_033057/adb_readonly_dump.txt)

69 个 gpt 分区 p1–p69。关键编号如上。*bak 分区是 OPPO/QCOM 防回滚备份, 非 A/B 槽。

## 来源 C — 镜像头

- 官方 `boot.img` (products_r11s_flash_rollback_20260801_0125/): Android bootimg **v1**, page 4096, kernel_size 0x00ec6540 (~15.5MB), **ramdisk_size 0 (无 ramdisk)**, kernel_addr 0x80000000, cmdline `console=ttyMSM0,115200n8 ... earlycon=msm_serial_dm,0xc170000`。
- `boot-debug.img`: 本地 4.19 调试内核 (非出厂), 19.2MB 内核 + 1.5MB ramdisk。
- `recovery.img`: 该目录无此文件。

## 对后续工作的含义

1. **Rootfs 归属 (Ubuntu/pmOS)**: 用 **userdata (p69, ~50GB, OTA 不碰)** 最安全; 避免 system (p66, verity 强制 + OTA 重写)。
2. **U-Boot 加载内核**: 从 boot (p21) 读。出厂 boot.img 无 ramdisk 无 DTB → U-Boot 必须自带 DTB 或用 appended-DTB 主线内核; 没有 DTB/DTBO 分区可读。
3. **mainline root= 注意**: 主线内核无 Android by-name udev 规则, 设备节点是 /dev/mmcblk0pNN (GPT 枚举) 或 root=PARTUUID=<gpt-uuid>; 不能假设 /dev/block/bootdevice/by-name/userdata 存在。

## Caveat

实机 boot/recovery/vbmeta 当前是第三方 DotOS 镜像 (recon/P0_ADB_EVIDENCE_REPORT.md), 非出厂对象; 但 69 分区编号是物理布局证据, 有效。
