# OPPO R11s 第三方 device tree / kernel source 取证报告

**取证日期：2026-07-30**  
**范围：** 仅从公开 GitHub 读取源码与元数据；未下载固件、未构建、未连接设备写入。  
**实机对照证据：** `recon/p0_adb_readonly_20260730_033057/`（活动 DT）与 `recon/P0_ADB_EVIDENCE_REPORT.md`。

> 用户明确设备为中国大陆 **OPPO R11s（无 t）**。仓库名称、代码中可能出现的 R11st/R11sPlus 不能自动视为本机材料；以下只采信能与本机活动 DT 字节级字段交叉对应的内容。

---

## 1. 结论

找到了**高度可信的 R11s 下游 kernel DTS 来源**，以及多个第三方 Android device tree。

最有价值的候选是第三方仓库 [`color597/android_kernel_oppo_sdm660-9`](https://github.com/color597/android_kernel_oppo_sdm660-9)，分支 `android-9-coloros-official`。它不是 OPPO 官方账号，不能作为官方回滚材料；但其 `17011` DTS 的 root 标识与本机运行 DT **逐字段一致**，因此可作为 R11s 板级下游参考的强证据。

**绝不直接将任何第三方 DTS 复制进主线 DTS，也不使用其镜像/脚本刷写。** 后续只将节点逐条与本机活动 DT、原厂固件 DTB/DTBO（取得后）和上游 binding 交叉验证。

---

## 2. 强交叉验证：`17011` DTS 与本机活动 DT

### 2.1 下载的第三方源码

- 仓库：[`color597/android_kernel_oppo_sdm660-9`](https://github.com/color597/android_kernel_oppo_sdm660-9)
- 分支：`android-9-coloros-official`
- 仓库自述：`ColorOS Linux kernel source code for OPPO R11/R11s series`
- 来源性质：**第三方 GitHub；非 OPPO 官方，源链未独立证明**
- 精确 DTS：`arch/arm64/boot/dts/17011/sdm660-pm660a-mtp-17011.dts`
- 已下载并归档：`recon/third_party_r11s_source_evidence_20260730_051654/color597_kernel_17011/`

该 DTS 的 root 节点为：

```dts
model = "Qualcomm Technologies, Inc. SDM 660 PM660 + PM660A MTP";
compatible = "qcom,sdm660-mtp", "qcom,sdm660", "qcom,mtp";
qcom,board-id = <8 0 17011>;
qcom,pmic-id = <0x0001001b 0x0001011a 0x0 0x0>,
               <0x0001001b 0x0002001a 0x0 0x0>,
               <0x0001001b 0x0202001a 0x0 0x0>;
```

### 2.2 实机活动 DT 对照

| 字段 | 下载 DTS | 本机 ADB 活动 DT | 结论 |
|---|---|---|---|
| `model` | `Qualcomm Technologies, Inc. SDM 660 PM660 + PM660A MTP` | 完全相同 | 一致 |
| `compatible` | `qcom,sdm660-mtp`, `qcom,sdm660`, `qcom,mtp` | 完全相同 | 一致 |
| `qcom,board-id` | `<8 0 17011>` | big-endian: `00000008 00000000 00004273`（0x4273 = 17011） | 一致 |
| `qcom,pmic-id` | 三组 PM660/PM660L ID | 实机同三组原始 cell 值 | 一致 |
| 显示 panel 命名 | `oppo17011samsung_sofeg01...1080p` | bootargs: `qcom,mdss_dsi_oppo17011samsung_sofeg01_s_1080p_cmd` | 一致 |
| 面板分辨率 | 1080×2160 | Android device config 1080×2160；与实际型号一致 | 一致 |

**判断：** 除非存在另一块使用相同 17011 board-id、相同三组 PMIC ID、相同 panel 命名、相同 DT root 标识的板卡，否则该 DTS 是本 R11s 硬件树的原始来源或非常近的未实质改动派生。这是目前最强的下游板级取证来源，但其发布者与 OPPO 的来源链仍未证实。

---

## 3. 对本项目直接有用的证据

### 3.1 DTS 继承结构

`sdm660-pm660a-mtp-17011.dts` 继承：

```dts
#include "sdm660.dtsi"
#include "sdm660-mtp.dtsi"
#include "msm-pm660a.dtsi"
#include "sdm660-internal-codec.dtsi"
```

这解释了为什么本机根 compatible 是 `sdm660-mtp` 而不是 `oppo,r11s`：R11s 是基于 Qualcomm MTP 基础 tree 的板级变体，品牌改动以 `17011` DTS、panel/供电/外设覆写的形式叠加。

### 3.2 已与实机一致的通用硬件锚点

第三方 tree 中可找到下列与实机已采集 DT 对应的架构：

- SDM660 + PM660/PM660L；
- eMMC `sdhci@c0c4000`；
- reserved-memory：`wlan_msa_guard@85600000`、`wlan_msa_mem@85700000`、`modem_fw_region@8ac00000`、`adsp_fw_region@92a00000`、`splash_region@9d400000`；
- USB-C/CC：`qcom,usbplug-cc-gpio = <&tlmm 58 0>`，并引用 `mdss_dp_usbplug_cc_active/suspend`；
- R11s panel：`dsi-panel-oppo17011samsung_sofeg01_1080p_cmd.dtsi`。

这些数据与实机活动 DT 中已确认的 USB、reserved-memory、PMIC、panel 命名相容。但本次未展开所有包含链，故 **USB DWC3/PHY 的最终 regulator/phandle 关系仍待逐项提取和与原厂 DTB 交叉验证**。

### 3.3 USB-first 路线的额外实证

第三方 TWRP common tree 的 `init.recovery.usb.rc` 明确使用 configfs，绑定 UDC `${sys.usb.controller}`，并为 OPPO 配置 VID `0x22d9`：

- ADB: PID `0x2769`
- MTP: PID `0x2764`
- mass storage: PID `0x2768`

实机曾以 `22d9:2768 OPPO SDM660-MTP` 枚举，完全对应该配置。这是独立验证：R11s 下游 device tree 已有 configfs gadget 路径，且与当前实机 USB 描述符吻合。它支持主线项目的 USB-first 方向，但 Android init 规则不能原样用于 Linux userspace。

---

## 4. 候选仓库分级

### A 级：板级参照（可作为只读源码证据）

1. [`color597/android_kernel_oppo_sdm660-9`](https://github.com/color597/android_kernel_oppo_sdm660-9) `android-9-coloros-official`
   - DTS：`arch/arm64/boot/dts/17011/sdm660-pm660a-mtp-17011.dts`
   - 仓库时间：创建 2021-08-27；最近 push 2022-07-23；非 fork、未 archived。
   - 优点：root `model` / `compatible` / board-id / PMIC ID 与本机逐项一致；有 `17011` panel DTS。
   - 限制：非官方账号、无正式来源链；只作为证据，不能当原厂来源。

2. [`YuxuanZuo/android_kernel_oppo_sdm660`](https://github.com/YuxuanZuo/android_kernel_oppo_sdm660) `KERNEL.LA.UM.7.2.r1-06900-sdm660.0-REL`
   - 仓库自述 R11/R11s CAFest kernel；同样包含 `arch/arm64/boot/dts/17011/sdm660-pm660a-mtp-17011.dts`。
   - 其文件树与 A 级候选的目标 DTS 文件名和关键内容一致，适合作为第二独立镜像来源。
   - 限制：同为第三方；尚未证明二者独立来源，不能将它们当独立一手证据。

### B 级：Android 打包参数 / USB 行为交叉证据

3. [`wuxianlin/android_device_oppo_r11s`](https://github.com/wuxianlin/android_device_oppo_r11s) `lineage-15.1`
   - R11s/R11st/R11sPlus 混用，因此**不能将特定 board 文件直接认定为 R11s 独有**。
   - 但 `BoardConfig.mk` 中 SDM660、UEFI、arm64、`boot`/`recovery` 64 MiB、`androidboot.usbcontroller=a800000.dwc3`、`earlycon=...0xc170000` 与本机 fastboot / DT 一致。
   - 用途：作为 USB controller、boot layout、boot cmdline 的辅助证据；不能作为 R11s exclusive DTS 证据。

4. [`YuxuanZuo/android_device_oppo_sdm660-common`](https://github.com/YuxuanZuo/android_device_oppo_sdm660-common) `android-11`
   - 明确是 R11/R11s/R15x/K1 共用，不能当 R11s 专属。
   - `BoardConfigCommon.mk` 记录 boot image header v1、4 KiB pages、64 MiB boot/recovery、kernel `Image.gz-dtb`。这些与真实 fastboot boot=64 MiB、recovery=64 MiB一致，header 版本仍需原厂 `boot.img` 解包验证。
   - `init.recovery.usb.rc` 的 VID/PID 与实机 USB 枚举强一致（见 3.3）。

5. [`oppo-sdm660-devs/android_device_oppo_R11s`](https://github.com/oppo-sdm660-devs/android_device_oppo_R11s) `lineage-18.1`
   - 明确 `TARGET_OTA_ASSERT_DEVICE := R11s`、`PRODUCT_MODEL := OPPO R11s`、`CONFIG_OPPO_TARGET_DEVICE="MSM_17011"`。
   - 是较新的 R11s 标识层配置，但仅 22 个文件、无 kernel/DTS，依赖未在该仓库内的 `sdm660-common`。
   - 用途：证明社区仍把 MSM_17011 对应 R11s；不能独自证明硬件节点。

6. [`YuxuanZuo/android_device_oppo_R11s`](https://github.com/YuxuanZuo/android_device_oppo_R11s) `android-11`
   - 明确 TWRP 产品 `OPPO R11s` / `PRODUCT_DEVICE := R11s`，但只有少量 recovery build 配置，无 kernel tree。
   - 用途：回收镜像的 Android device 配置参考；非主线 DTS 来源。

---

## 5. 已保存的一手下载副本与 hash

目录：`recon/third_party_r11s_source_evidence_20260730_051654/`

下载时的 raw URL、分支和 SHA-256 已记录到 `SHA256SUMS`。关键文件：

| 文件 | SHA-256 |
|---|---|
| `color597_kernel_17011/sdm660-pm660a-mtp-17011.dts` | `41228d7ec184517e1a19e725ef64641ac0813cf55bc497512cd71f9efa109424` |
| `color597_kernel_17011/sdm660-mtp.dtsi` | `cf406de81a834723e274ad370173c3cb2fdf024481a440ed455859b78e3fd05d` |
| `color597_kernel_17011/sdm660.dtsi` | `cebe477d2d309ceb9363a0ef5f9d2a3001dd51c3c6069bee8c45d993d0ceded1` |
| `color597_kernel_17011/dsi-panel-oppo17011samsung_sofeg01_1080p_cmd.dtsi` | `1c96ee4b17066c9a67da99ef9ed3d095f03326e4ae00a115ae3773197812bfa1` |

---

## 6. 后续建议（仍然只读）

1. 将 A 级 kernel tree 完整 clone 到一个时间戳证据目录，固定 commit SHA，并将 `17011` DTS include closure 扁平化；不放入未来 upstream `linux/` tree。
2. 用实机活动 DT逐节点比对：DWC3/QUSB2 的 `reg`、clock/reset、`usb-phy` phandle、regulator supply、extcon；eMMC；reserved-memory；UART；panel。
3. 继续取得 OPPO 原厂包或原厂 DTB/DTBO 后，将第三方 DTS 逐字段做三方比对（官方 DTB vs 活动 DT vs 17011 DTS）。
4. 在三方比对完成前，不生成 R11s 主线 DTS，不构建/打包 boot 镜像。
