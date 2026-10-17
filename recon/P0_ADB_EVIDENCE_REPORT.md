# R11s 实机只读取证报告（ADB 通道）

**取证日期：2026-07-30**  
**采集方式：** 手机开机进系统，USB 调试授权，主机 `adb shell` 只读 getprop / sysfs / /proc。全程未写分区、未安装、未推送。  
**取证目录：** `recon/p0_adb_readonly_20260730_033057/`

> 本报告只记录实机一手输出。凡无法由本次实机数据支撑的推断，标注【未证实】并列入后续取证项。

---

## 1. 设备身份（一手实机）

| 项 | 值 | 来源 |
|---|---|---|
| 商品型号 | OPPO R11s | `ro.product.model` / `ro.product.name` |
| 品牌/厂商 | OPPO | `ro.product.brand` / `ro.product.manufacturer` |
| 设备代号 | R11s | `ro.product.device` |
| SoC 平台 | sdm660 | `ro.product.board` / `ro.board.platform` |
| SoC 型号 | SDM660（soc0 machine=SDM660, soc_id=317, rev=1.0） | `/sys/devices/soc0/*` |
| ABI | arm64-v8a | `ro.product.cpu.abi` |
| USB Vendor:Product | 22d9:2768（OPPO, SDM660-MTP） | `lsusb` |
| 序列号 | 9144dacf | `ro.boot.serialno` |
| eMMC | DH6DMB（manfid 0x000015），约 58.3 GiB（122142720 × 512B） | `/sys/block/mmcblk0/device/*` |
| 内存 | 约 3.8 GiB | `/proc/meminfo` |

**CPU（一手）：** AArch64, implementer 0x51（Qualcomm）, part 0x801, revision 4。8 核（cpuinfo 显示 0–7）。

**qcom 硬件 ID（DT root，一手解码）：**

- `qcom,msm-id = 0x0000013d`（=317 → SDM660）
- `qcom,board-id = 0x00000008, 0x00004273`
- `qcom,pmic-id = (0x0001001b,0x0001011a),(0x0001001b,0x0002001a),(0x0001001b,0x0202001a)` → PM660 + PM660L 组合
- DT root `compatible = "qcom,sdm660-mtp qcom,sdm660 qcom,mtp"`
- DT root `model = "Qualcomm Technologies, Inc. SDM 660 PM660 + PM660A MTP"`

---

## 2. 运行中的系统不是原厂 ColorOS（关键发现）

实机 getprop 显示当前运行 **DotOS v5.2 第三方 ROM**，证据：

- `ro.dot.display.version = DotOS-v5.2-R11s-UNOFFICIAL`
- `ro.dot.version = dotOS-R-v5.2-arm64_bvN-VANILLA-UNOFFICIAL-20211014-1749`
- `ro.dot.fingerprint = dotOS/v5.2/11//20211014-1749`
- `ro.modversion = v5.2`
- `ro.build.flavor = treble_arm64_bvN-userdebug`
- `ro.build.description = treble_arm64_bvN-userdebug 11 RD2A.211001.002 eng.mohan.20211014.174946 test-keys`（test-keys = 非官方签名）
- `ro.build.type = userdebug`（非 user）

**运行内核非原厂：** `/proc/version` =
`Linux version 4.4.153-perf-ga9ea30b59cfc-00026-g40ba3797e045 (wenhao@WenHao-ArchLinux) (ZyC clang version 19.0.0git ...) #1 SMP PREEMPT Fri Oct 4 12:41:45 CST 2024`
—— 由 `wenhao@WenHao-ArchLinux` 用 ZyC clang 19 于 2024-10-04 自编，**社区下游内核，非 OPPO 原厂**。

### 2.1 unlock / verified boot 状态自相矛盾（待 fastboot 实测）

`getprop` 给出：
- `ro.boot.flash.locked = 1`
- `ro.boot.verifiedbootstate = green`
- `ro.boot.vbmeta.device_state = locked`
- `ro.boot.veritymode = enforcing`
- `sys.oem_unlock_allowed = 1`

但 DT `chosen/bootargs`（静态）含 `androidboot.verifiedbootstate=orange androidboot.selinux=permissive`。

一组 green/locked/enforcing 却能跑 test-keys 自编内核与 DotOS，逻辑上不成立。结论：**上述 bootloader 状态值不可由 getprop 单独采信，必须用 `fastboot getvar` 实测澄清。** 在实测前不得假设设备已解锁，也不得假设原厂 boot 仍可验证。

### 2.2 对取证策略的影响

由于当前 `boot`（mmcblk0p21）、`recovery`（p23）、`vbmeta`（p62）已被当前第三方系统使用：
- **设备当前分区不是原厂回滚材料。** 从设备 dump 出来的 boot/recovery 是 DotOS 镜像，不是 OPPO 原厂。
- 原厂 boot/recovery/vbmeta/分区表必须从 **OPPO 官方 R11s ColorOS 固件包**下载取得；`dtbo` 在本次 ADB by-name 分区表中未出现，设备布局是否含该分区尚未证实。
- 即便如此，本次 dump 的活动设备树（见第 3 节）来自实机下游内核，仍是**一手板级硬件证据**（地址、节点、寄存器来自真实 SoC），可用于后续 R11s 最小 DTS 的交叉验证。

---

## 3. 活动设备树板级证据（一手，来自 /sys/firmware/devicetree/base）

> 节点来自社区下游内核的 DT，但反映真实 SDM660 + R11s 板级地址与配置。仅作为板级参考证据，不等于原厂 DTS。

### 3.1 USB（gadget-first 调试核心）

- **SSUSB / DWC3（活跃，当前承载 adb gadget）：**
  - `soc/ssusb@a800000`，`compatible = "qcom,dwc-usb3-msm"`
  - 子节点 `dwc3@a800000`，`compatible = "snps,dwc3"`，`maximum-speed = "high-speed"`，`usb-phy` 指向 PHY phandle
  - 供电：`USB3_GDSC-supply`、`vbus_dwc3-supply`
  - `extcon`（角色/连接检测）phandle 存在
  - **UDC 实时状态：** `/sys/class/udc/a800000.dwc3` state=`configured` —— 证明 DWC3 peripheral 链路当前正在工作（adb 即走此通道）
- **HSUSB（USB2，禁用）：** `soc/hsusb@c200000`，`compatible = "qcom,dwc-usb3-msm"`，`status = "disabled"`
- **QUSB2 PHY：**
  - `soc/qusb@c012000`，`compatible = "qcom,qusb2phy"`，`status = ok`（有 `qcom,qusb-phy-init-seq`）
  - `soc/qusb@c014000`，`compatible = "qcom,qusb2phy"`（第二组）
- **USB 角色 / CC 检测：** `qcom,dp_ctrl@c990000`（`qcom,mdss-dp`）含 `qcom,usbplug-cc-gpio`、`qcom,dp-usbpd-detection`；pinctrl 含 `mdss_dp_usbplug_cc_active/suspend`
- **USB 音频辅助：** `qcom,msm-dai-q6-usb-audio-rx/tx`、`usb_audio_qmi_dev`

### 3.2 PMIC / SPMI

- `soc/qcom,spmi@800f000`，`compatible = "qcom,spmi-pmic-arb"`
- 子节点：`qcom,pm660@0`、`qcom,pm660@1`、`qcom,pm660l@2`、`qcom,pm660l@3`
- 与 `qcom,pmic-id` 一致：PM660 + PM660L

### 3.3 reserved-memory（内存布局，一手）

| 区域 | 兼容 | 备注 |
|---|---|---|
| `adsp_fw_region@92a00000` | removed-dma-pool | no-map 类 |
| `adsp_region` | shared-dma-pool | size 0x00800000 |
| `cdsp_fw_region@94c00000` | removed-dma-pool | |
| `modem_fw_region@8ac00000` | removed-dma-pool | |
| `pil_mba_region@94a00000` | removed-dma-pool | |
| `qseecom_region` | shared-dma-pool | size 0x01400000 |
| `removed_regions@85800000` | removed-dma-pool | |
| `secure_region` | shared-dma-pool | size 0x05c00000 |
| `splash_region@9d400000` | — | 开机画面 |
| `venus_fw_region` | shared-dma-pool | |
| `wlan_msa_guard@85600000` | removed-dma-pool | |
| `wlan_msa_mem@85700000` | removed-dma-pool | |
| `linux,cma` | shared-dma-pool | size 0x02c00000 |

> **ramoops/pstore 节点未在活动 DT 出现**（`/sys/fs/pstore` 为空）。主线 ramoops 需在最小 DTS 中新增保留区，地址不得与上述区域重叠——后续需用原厂 DTB/DTBO 或下游 DTS 进一步交叉核对。

### 3.4 UART（早期调试备选）

- `uart@c1af000` `compatible="qcom,msm-hsuart-v14"` `status=ok` —— **唯一启用**的 UART
- `uart@c16f000` / `c170000` / `c1b0000` 均 `disabled`
- `chosen/bootargs` 含 `console=ttyMSM0,115200 ... earlycon=msm_serial_dm,0xc170000`（注意 earlycon 指向 c170000，与 status=ok 的 c1af000 不同——后续需核实哪个是物理可达 UART）
- `printk.disable_uart=1`（当前 UART 输出被关闭）

### 3.5 eMMC / 存储

- `soc/sdhci@c0c4000`，`compatible="qcom,sdhci-msm-v5"`，`status=ok`
- `chosen/bootargs` 含 `androidboot.bootdevice=c0c4000.sdhci` —— 确认 eMMC 是启动盘
- 分区表：69 个分区，`boot=p21 / recovery=p23 / vbmeta=p62 / system=p66 / vendor=p67 / userdata=p69`，含 A/B 备份（bootbak=p22、recovery 含于 p23、vbmetabak=p63 等）及 `xbl=p10 / tz=p12 / hyp=p16 / rpm=p14 / pmic=p18 / modem=p64 / dsp=p34 / persist=p5`

---

## 4. 原厂固件已不在设备分区

当前 `ro.build.fingerprint = OPPO/R11s/R11s:9/PKQ1.190414.001/1588166940:user/release-keys`（Android 9 fingerprint 字段）与运行 Android 11 的 DotOS 不符。该字段可能是刷入 DotOS 前保留的旧原厂值，但其来源未由本次采集证明，不能作为原厂固件版本依据。

**精确原厂 ColorOS build 号本次无法从实机确定**（被 DotOS 覆盖）。需从 OPPO 官方下载对应 R11s 固件包。

---

## 5. 下一步取证门禁

1. **fastboot getvar 实测**（P0-B）：澄清 unlock 真实状态、bootloader 版本、slot、`fastboot boot` 支持——需用户当次确认后进入 bootloader。
2. **官方固件下载**（P0-C）：按已确认的 R11s（无 t、中国大陆公开版）从 OPPO 官方/可信镜像获取匹配的 ColorOS 固件包，计算 SHA-256，解包取证原厂 boot/recovery/vbmeta/分区表；是否存在 dtbo 仅在原厂包分区清单中确认后再处理。
3. 交叉核对本次活动 DT 的 USB/reserved-memory 地址与原厂 DTB 是否一致。

---

## 6. 文件清单

- `adb_readonly_dump.txt` — getprop / 分区 / mount / cpuinfo / soc0
- `adb_dtb_usb_iomem.txt` — DT 可用性 / USB 节点 / UDC / pstore / eMMC
- `device_tree_live/root_compatible.txt` — root compatible/model/msm-id/board-id/pmic-id
- `device_tree_live/ssusb_a800000.txt` — SSUSB DWC3 节点属性
- `device_tree_live/hsusb_c200000.txt` — HSUSB 节点属性
- `device_tree_live/usb_pmic_reserved.txt` — USB/SPMI/reserved-memory/sdhci 摘要
- `device_tree_live/reserved_uart_emmc_boardid.txt` — reserved-memory/UART/eMMC/board-id/chosen bootargs
- `region_version_precise.txt` — 区域/版本/DotOS 证据
