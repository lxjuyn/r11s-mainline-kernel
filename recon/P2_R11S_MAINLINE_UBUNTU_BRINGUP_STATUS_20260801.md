# P2 — R11s 主线 Ubuntu bring-up 状态报告（2026-08-01）

> **性质：** 主机侧状态记录。仅汇总已完成的主机侧构建与归档、fastboot boot 计划及未决门禁。
> **边界：** 本文不改动内核、DTS、rootfs 与任何设备；未生成或测试可刷镜像；不构成任何写入许可。
> **目标设备：** Oppo R11s（无 t、中国大陆公开版），Qualcomm SDM660 / arm64（17011 board-id）。

---

## 0. 一句话状态

主线 Ubuntu 启动的**主机侧基线已齐备**：Linux 7.2-rc5 Image、R11s 专属 DTB、USB-first initramfs、Ubuntu arm64 rootfs 均已构建并归档（哈希见下）。但 **boot.img 尚未打包完成、`fastboot boot` 支持尚未实测**——离首次非破坏性 RAM boot 还有两个明确门禁（§6 G1/G2）。所有产物均为**不可刷/未上板**状态。

## 1. Linux7 Image 构建（SHA-256 `23de027d…`）

| 项 | 值 |
|---|---|
| 产物 | `backups/products/products_mainline_linux7_ubuntu_reference_20260731_2223/Image`（51,128,832 B） |
| SHA-256 | `23de027d37e06403379619bd65276cf7851a2d8fabaf6767f646026a4c1212bf` |
| 源码 | `/home/<user>/claude/r11/linux`（Linux **7.2-rc5**，VERSION=7 PATCHLEVEL=2 SUBLEVEL=0 EXTRAVERSION=-rc5） |
| 工具链 | aarch64-linux-gnu-gcc 13.3.0（Ubuntu 13.3.0-6ubuntu2~24.04.1） |
| 构建命令 | `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=build/mainline_linux7_ubuntu_ref -j16 Image dtbs` |
| 配置 | arm64 `defconfig` + `out/mainline_r11s_ubuntu_usb.config`（merge_config 合并）；`.config` SHA-256 `197cfdf9…` |
| 构建状态 | OK（exit 0，日志无 error/warning）；同批产出参考 DTB `sdm660-xiaomi-lavender.dtb`（SHA-256 `d9a27270…`） |

构建说明出处：`backups/products/products_mainline_linux7_ubuntu_reference_20260731_2223/README` 与 `SHA256SUMS`；合并/defconfig 日志见 `out/mainline_linux7_*`。

> **定性：** 这是"Linux7/SDM660 Ubuntu 参考构建"，**不是**已宣称可启动的 R11s 镜像——README 明确声明未创建 R11s DTS、未打包 boot.img/initramfs。其价值是验证 arm64 工具链、USB-first config（`CONFIG_USB_DWC3/DWC3_QCOM/CONFIGFS/ACM/ECM/NCM` 见 `out/mainline_r11s_ubuntu_usb.config`）与 Linux7 依赖链，并为后续打包提供 Image。

## 2. R11s DTB 构建（SHA-256 `a7b109f7…`）

| 项 | 值 |
|---|---|
| 产物 | `out/r11s_dtb_build_20260731_224315/sdm660-oppo-r11s.dtb`（49,813 B，DTB v17） |
| SHA-256 | `a7b109f7348f946ea383f926fdc5c4b9100eb0461eba7a39e7896b1d5ccf20ed` |
| 内核树 | Linux 7.2-rc5（`linux/arch/arm64/boot/dts/qcom/sdm660-oppo-r11s.dts`） |
| 工具链 | aarch64-linux-gnu-gcc 13.3.0 |
| DTC 状态 | **BUILD OK，无 warning/error**（`build_qcom_direct2.log`） |

构建注意（非 DTS 缺陷）：字面 `make sdm660-oppo-r11s.dtb` 在 7.2-rc5 的 `O=` 下失败，属内核 build 系统对子目录 DTB 目标的解析限制（lavender 同样失败）；等价成功路径是经 `scripts/Makefile.build obj=arch/arm64/boot/dts/qcom` 编译。详见 `out/r11s_dtb_build_20260731_224315/README.md`。

**DTB 静态回读要点**（README 第 "Static verification" 节，kernel dtc + fdtdump 双工具一致）：

- **USB（设计核心，正向）**：`usb3@a8f8800` status=okay 且含 `qcom,select-utmi-as-pipe-clk`；`usb3_dwc3@a800000` `maximum-speed="high-speed"`、`dr_mode="peripheral"`、`phys=<0x35>` phy-names=usb2-phy；`qusb2phy0@c012000` status=okay，供电 phandle 指向 PM660L L1 / PM660 L10 / PM660L L7。
- **eMMC**：`sdhc_1`（`mmc@c0c4000`）status=okay、bus-width=8、non-removable。
- **按设计缺失（负向）**：无 extcon、无 ramoops/reserved range、无 gpio-keys、无 HS400/HS200/CQE、无 simple-framebuffer；SuperSpeed PHY `phy@c010000` 与 secondary HSUSB `usb@c2f8800` 显式 disabled——**USB2-only peripheral bring-up**。
- **未证实项仍在 DTB 之外**：ramoops 地址未选、extcon/SMB2 角色检测未过 upstream binding review（见 §6 G6/G7 与 `recon/P2_R11S_MAINLINE_DTS_DESIGN.md` 2026-08-01 更新）。

## 3. initramfs 构建（SHA-256 `af5bb948…`）

| 产物 | 大小 | SHA-256 |
|---|---|---|
| `out/r11s_ubuntu_initramfs_20260731_2302/r11s_ubuntu_initramfs.cpio` | 1,942,528 B | `4edf45d8d8ff6094700bf08620b1cca5bb69f01e0e6ea62fcfbba99dc28c4bb3` |
| **`r11s_ubuntu_initramfs.cpio.gz`（推荐作为 external initrd）** | 1,009,416 B | **`af5bb948e50c57c4d2cc59223fce5284e1343c99ff487d113417bcfa78c61c46`** |
| `r11s_ubuntu_initramfs.cpio.zst` | 898,047 B | `6d975bd1f9969b26d5749380f9fc752b0b19a34521d72fedbb66e8cad2f343bb` |

内容：arm64 **static busybox 1.36.1**（官方 ports.ubuntu.com 包，SHA-256 `d96535e0…`）+ 129 applet symlink + 8 设备节点，共 174 entries；`/init` 依次：挂载 proc/sysfs/devtmpfs/devpts/**configfs** → stdio→`/dev/console` → configfs 创建 USB gadget（CDC-**ACM** 默认绑定，ECM 块注释备选，UDC=`a800000.dwc3`，`idVendor/idProduct=0x1d6b:0x0104` **占位**）→ 解析 `root=`/`rootfstype=`（**绝不猜测分区**）→ `switch_root` 到 `/sbin/init`；失败落 busybox rescue shell。详见 `out/r11s_ubuntu_initramfs_20260731_2302/README.md`（§3 init 行为、§5 证据门禁、§6 验证）。

**已完成的主机侧验证**：qemu-aarch64 下 arm64 busybox 可运行且关键 applet 在、`init` 通过 `sh -n`、configfs 序列对 mock 树执行结果正确、cpio 解包 174 entries 且 `diff -r staging/` 一致（含设备节点）。
**未执行**：上板启动（本轮明确禁止，见 README §6 第 6 条）。

## 4. Ubuntu rootfs（约 235M，arm64）

| 项 | 值 |
|---|---|
| 路径 | `/home/<user>/claude/r11/rootfs/ubuntu-arm64`（`du -sh` ≈ **235M**） |
| 基底 | Ubuntu Base **Noble 24.04.3 arm64**（`out/ubuntu-base-24.04.3-base-arm64.tar.gz`，SHA-256 `7b2dced6…`） |
| init | systemd-sysv 255.4（`/sbin/init -> ../lib/systemd/systemd`），usr-merged，glibc 2.39 |
| 关键组件 | udev 255.4、iproute2 6.1.0、kmod 31、isc-dhcp-client 4.4.3（全部 aarch64 ELF 已核） |
| configfs 挂载 | 用户态完备：`sys-kernel-config.mount` 已启用 + `99-systemd.rules` UDC→`usb-gadget.target`；内核侧 `CONFIG_CONFIGFS_FS=y` 内置 |

**审计结论（`out/firstboot_init_r11s_audit_20260801.md`）：PASS（CONDITIONAL）。** systemd init、udev、ip、dhclient、configfs 挂载全在位且为 aarch64；两个使用层 gap：网络（DHCP）不会自动拉起、USB gadget console getty 未配置（`<EMAIL>` 需启用）——均为 first-boot 脚本可带出的配置，非 rootfs 结构性缺失。busybox 在 rootfs 中缺失但**不构成风险**（systemd 承担 init）。首次启动验证预案见该文 §6 与 `out/FIRSTBOOT_INIT_ECM_NCM_PLAN.md`。rootfs 构建说明见 `rootfs/ubuntu-arm64/ROOTFS_BUILD_README.md`。

## 5. fastboot boot 计划（RAM 临时启动，非破坏）

**bootloader 已取证的只读事实**（`recon/P0_B_FASTBOOT_EVIDENCE_REPORT.md`）：

- `unlocked=yes`（实测；ADB 侧 `flash.locked=1` 与之矛盾，以 bootloader 实测为准）、`secure=yes`、`product=sdm660`、`variant=SDM EMMC`、`kernel=uefi`（Qualcomm ABL 链）。
- `max-download-size=536870912`（512 MiB）；`boot`=64 MiB raw、`recovery`=64 MiB、`vbmeta`=64 KiB；**无 `dtbo`**（fastboot 与 ADB by-name 均未暴露）。
- 标准 A/B slot 键（`current-slot`/`slot-count`）未实现/未暴露；`bootbak/vbmetabak` 存在但语义未证实。
- **`fastboot boot` 是否支持——未实测。** getvar 无键可推断该能力；实测须真正发起一次 RAM boot，属"改变设备运行状态"操作，需单独当次批准。

**打包参数**（依据 `recon/P2_R11S_MAINLINE_DTS_DESIGN.md` 2026-08-01 更新：R11s boot 流为 **ABL appended-DTB** 契约，DTB 附加在 boot 镜像尾部，无独立 DTBO；`tools/mkbootimg_v1.py` 实现 header v1 打包，page_size 0x1000、kernel_addr base+0x8000、ramdisk_addr base+0x1000000、tags_addr base+0x100，对齐官方 C.19 boot.img 布局）：

```
# 目标产物（构建中）：out/boot.img = Image.gz + 附加 DTB + initramfs .cpio.gz
# 待执行（门禁通过 + 用户当次确认后）：
adb reboot bootloader
fastboot boot /home/<user>/claude/r11/out/boot.img
```

**执行与回滚**：

- 编排脚本：`tools/r11s_fastboot_boot_test.sh`（默认 dry-run 只读采集；`--execute` 且通过 hash/设备门禁后执行，可 `--yes` 跳过当次确认——自动化慎用）；`tools/fastboot_boot_prep_draft.sh`（只读准备草稿）。两者均**绝不 flash 分区**。
- `fastboot boot` 的固有性质：仅把 Image/DTB/initramfs 载入内存临时启动，**不写任何分区**；重启/断电即回到设备 boot 分区原有 boot，无需回滚材料（`backups/products/products_r11s_flash_rollback_20260801_0125/README.md` §4）。但这**不等于**本机已验证支持（仍需 §6 G1 实测）。
- 持久化刷写回滚对象（仅备而不用）：官方 **C.19 `boot.img`**（SHA-256 `5949396d14aa8113cbd47e0963fb056f1c5e47c182419be29d681651bc1c0dec`，来源链=官方 ColorOS CDN OTA，已字节级归档于 `backups/products/products_r11s_flash_rollback_20260801_0125/`）；用户提供的"通刷底包"因签名完整性失败**禁用**（`recon/P0_C_LOCAL_C19_ARCHIVE_INTEGRITY_AUDIT.md`）。
- 测试脚本对 RAM boot 被拒/黑屏的恢复：`fastboot reboot`、长按电源 ~10s 强断电、`fastboot reboot bootloader`（`tools/r11s_fastboot_boot_test.sh` 步骤 7）。

## 6. Outstanding gates（未决门禁）

- **G1（关键）`fastboot boot` 支持未实测。** bootloader 未暴露可推断能力键；需在打包完成、hash 复核通过后，经用户当次明确批准发起一次 RAM boot 确认（`recon/P0_B_FASTBOOT_EVIDENCE_REPORT.md` §1.2、`recon/r11s-fastboot-gates.md` §1）。
- **G2（关键）boot.img 未打包完成。** 当前 `out/boot.img` 尚未生成（`out/test_flash_progress.md` 状态 NOT YET FLASHED / build in progress，`wf-build-bootimg` 进行中）；`tools/mkbootimg_v1.py`、Image、DTB、initramfs 均就绪待组合。打包参数（header v1、appended-DTB、offset）须按 §5 对照官方 C.19 boot.img 再核（`recon/P2_R11S_MAINLINE_DTS_DESIGN.md` boot-image packaging 表）。
- **G3 原厂固件完整回滚包未闭环。** 已取得并 hash 官方 C.19 OTA 与 `boot.img`（`recon/P0_C_LOCAL_OTA_1170_AND_DTS_STATIC_AUDIT.md`、`P0_C_R11S_FIRMWARE_CANDIDATE_REVIEW.md`）；但 OZIP 内 system/vendor/recovery/vbmeta 及分区清单仍未完整解密/提取/审计（`recon/P0_C1_OZIP_AUDIT_TOOL_PIN.md`；`STATUS.md` P0-C 节）。`dtbo` 是否存在待分区清单确认。
- **G4 ramoops/pstore 前置缺失。** DTB 无 ramoops 节点；完整 RAM + bootloader reservation 审查未做，**ramoops 地址不得猜测**（`recon/P2_R11S_MINIMAL_DTS_EVIDENCE_MATRIX.md`、`recon/P2_R11S_MAINLINE_DTS_DESIGN.md` Reserved-Memory 节）。USB gadget 无法覆盖 DWC3 probe 前的早期崩溃，需此路径（`CLAUDE.md` §0）。
- **G5 早期崩溃证据路径未闭环。** TTL/UART 难以引出；主调试线为 USB gadget，但不覆盖 probe 前崩溃；需 pstore/ramoops、framebuffer 或 bootloader 可见证据（`recon/usb_gadget_debug_boot_safety.md`）。
- **G6 DWC3 extcon/SMB2 角色检测未过 upstream binding review。** 实机 phandle 确认角色检测经 extcon→SMB2 charger（pmi8998）而非 ID GPIO/laverberry extcon；DTS 改写时不得复制 lavender extcon 或 ID GPIO（`recon/P2_R11S_MAINLINE_DTS_DESIGN.md` 2026-08-01 更新，gate 5 未解除）。
- **G7 QUSB2 供电 rail→binding 名映射未过审。** live phandle 解析 L1/L10/L7 为 QUSB2 HV/1.8V/1.9V，但 `qcom,qusb2-phy` 的 `vdd/vdda-pll/vdda-phy-dpdm-supply` 匹配仍待独立 upstream-binding review（gate 5）。
- **G8 外设全部后置。** 面板/触摸/音频/Wi-Fi/BT/modem/DSP/camera/VOOC 均不在首版范围内（`recon/P2_R11S_MAINLINE_DTS_DESIGN.md` "Future Minimal Node Intent"、`PLAN.md` P4）。rootfs first-boot 仅验证 USB 枚举→CDC ACM→ECM/NCM→shell（`out/firstboot_init_r11s_audit_20260801.md` §6）。
- **G9 每次设备操作需当次批准。** 任何解锁/刷写/写分区/RAM boot 均须先展示命令、目标、完整回滚路径与风险并取得用户当次确认（`CLAUDE.md` §3、`out/test_flash_progress.md` §Policy）；9008/EDL 仅原厂恢复路径。

## 7. 引用的 recon / 证据文档

- `recon/P0_B_FASTBOOT_EVIDENCE_REPORT.md` — fastboot getvar 实测（unlocked、分区表、max-download-size）
- `recon/P0_ADB_EVIDENCE_REPORT.md` — ADB 实机只读取证（分区表 boot=p21 等）
- `recon/r11s-fastboot-gates.md` — `fastboot boot` 证据门禁（未取证）
- `recon/P2_R11S_MAINLINE_DTS_DESIGN.md` — R11s DTS 设计基线 + 2026-08-01 更新（ABL appended-DTB、boot packaging、extcon/SMB2、QUSB2 rails）
- `recon/P2_R11S_MINIMAL_DTS_EVIDENCE_MATRIX.md` — 最小 DTS 证据矩阵
- `recon/R11S_17011_DTS_LIVE_DT_MATRIX.md` — 17011 实机 DT 证据矩阵
- `recon/usb_first_initramfs_gadget_design.md` — USB-first initramfs/gadget 设计
- `recon/usb_gadget_debug_boot_safety.md` — gadget 启动安全门禁与 pstore/ramoops 互补
- `recon/P0_C_LOCAL_OTA_1170_AND_DTS_STATIC_AUDIT.md`、`recon/P0_C_R11S_FIRMWARE_CANDIDATE_REVIEW.md`、`recon/P0_C_LOCAL_C19_ARCHIVE_INTEGRITY_AUDIT.md`、`recon/P0_C1_OZIP_AUDIT_TOOL_PIN.md` — 原厂固件审计
- `backups/products/products_mainline_linux7_ubuntu_reference_20260731_2223/{README,SHA256SUMS}` — Linux7 Image 构建
- `backups/products/products_r11s_flash_rollback_20260801_0125/README.md` — 回滚对象（官方 C.19 boot.img）
- `out/r11s_dtb_build_20260731_224315/README.md` — R11s DTB 构建与静态验证
- `out/r11s_ubuntu_initramfs_20260731_2302/README.md` — initramfs 构建与验证
- `out/firstboot_init_r11s_audit_20260801.md`、`out/FIRSTBOOT_INIT_ECM_NCM_PLAN.md`、`out/test_flash_progress.md` — rootfs first-boot 审计与测试进度
- `tools/r11s_fastboot_boot_test.sh`、`tools/fastboot_boot_prep_draft.sh`、`tools/mkbootimg_v1.py` — RAM boot 编排与 boot.img 打包
- `PLAN.md`、`STATUS.md` — 阶段门禁与状态基线

---

*本文件仅记录主机侧已证实状态与未决门禁；未修改内核/DTS/rootfs，未生成或测试可刷镜像。*
