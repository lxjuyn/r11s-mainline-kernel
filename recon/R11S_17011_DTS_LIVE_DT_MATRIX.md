# R11s 17011 下游 DTS 与实机活动 DT：关键节点证据矩阵

**取证日期：2026-07-30**  
**范围：** 已归档的实机 ADB 活动 DT 摘要，与第三方下游 kernel DTS 的只读比对。未构建、未生成镜像、未写设备。  
**实机证据：** `recon/p0_adb_readonly_20260730_033057/device_tree_live/`。  
**下游来源：** 第三方仓库 `color597/android_kernel_oppo_sdm660-9`，分支 `android-9-coloros-official`，比对时 HEAD 为 `2a33e8b03a6ec1c3b48377704e27a09788489061`。该仓库不是 OPPO 官方来源；它只作为可复核的下游参照，不能直接转化为 R11s 主线 DTS。

> `17011` 顶层 DTS 的 model、compatible、board-id 和 PMIC ID 已与实机活动 DT 精确一致。这证明该 tree 是强下游参照；不证明其中来自 `sdm660-mtp.dtsi` 的 MTP 基础覆写就是 R11s 专属板级事实。

## 证据等级

- **精确**：实机采集明确包含同一地址、状态或原始属性值。
- **SoC/MTP 参考**：来自 SDM660 或 Qualcomm MTP include，未由实机逐项确认。
- **未验证**：当前采集没有足以支持该属性、目标 phandle 或物理连接的原始数据。

| 范围 | 下游 DTS 参照 | 实机活动 DT 原始证据 | 等级 | 主线 DTS 使用边界 |
|---|---|---|---|---|
| R11s 17011 身份锚点 | `17011/sdm660-pm660a-mtp-17011.dts`：`qcom,board-id = <8 0 17011>`，同 model/compatible/PMIC IDs | `root_compatible.txt` 的 model、compatible、board-id 三 cell 和 PMIC IDs 一致 | **精确** | 可用作板级身份交叉锚点；不等同于可直接搬用下游节点。 |
| DWC3 主控制器 | `ssusb@a800000`；`qcom,dwc-usb3-msm`；reg `0xa800000/0xfc100`、`0xc016000/0x400`；子 `dwc3@a800000` | `ssusb_a800000.txt` 有同 compatible、两段 reg、三 IRQ 与子 DWC3；UDC `a800000.dwc3` 为 `configured` | **精确** | 首版 USB gadget 的地址/控制器方向强证据；须按上游 binding 重建，不能搬下游 bus/DBM/IPA 专有属性。 |
| USB HS-only / SS PHY | 下游 `dwc3@a800000` 为 `maximum-speed = "high-speed"`、`usb-phy = <&qusb_phy0 &usb_nop_phy>`；`ssphy@c010000` disabled | 实机子 DWC3 解码为 `high-speed`；原始 `usb-phy` cells 是 `0x7b,0x182` | **精确**（HS-only 与 PHY 关系）；SS PHY 节点未逐项导出 | 首版仅以 USB2 HS peripheral/gadget 为目标；不启用 SuperSpeed PHY。 |
| DWC3 角色/VBUS | 下游 `extcon = <&pm660_charger>`、`vbus_dwc3-supply = <&smb2_vbus>` | 实机有 `extcon=0x181`、`vbus_dwc3-supply=0x84`，但未导出 phandle 目标 | **属性精确；目标未验证** | 不得直接指定 charger/regulator；先导出 phandle 目标及其 PMIC/Type-C 链。 |
| QUSB2 primary PHY | `qusb@c012000`、`qcom,qusb2phy`；启用 init sequence 以 `b8 80 8f 84 83 88 c7 8c` 开始 | `usb_pmic_reserved.txt` 有同 compatible、reg 和相同 init-seq 原始 cells 前缀 | **精确** | 是 QUSB2 参数强证据；供电 phandle 仍须逐项验证，并转换为上游 binding。 |
| 次级 HSUSB | `hsusb@c200000` 与子 DWC3 为 disabled | `hsusb_c200000.txt` 有相同 compatible、reg、IRQ、`status=disabled` | **精确** | 首版不启用。 |
| eMMC | `sdhci@c0c4000`、`qcom,sdhci-msm-v5`、两段 reg；MTP include 设 non-removable 与 HS400/HS200 | `reserved_uart_emmc_boardid.txt` 有同 compatible、status=ok、两段 reg；bootargs `androidboot.bootdevice=c0c4000.sdhci` | **精确**（控制器与启用）；**SoC/MTP 参考**（供电、pinctrl、时序） | 可作为上游 SDM660 eMMC 根节点锚点；不能直接采用 MTP 供电/pinctrl/高速参数。 |
| SD 卡 | `sdhci@c084000`；MTP include 提供 CD GPIO、3V 供电 | 实机只确认节点存在 | **未验证** | 后置；不得使用 MTP CD GPIO 或 regulator。 |
| fixed reserved-memory | `wlan_msa_guard@85600000`、`wlan_msa_mem@85700000`、`removed_regions@85800000`、`modem_fw_region@8ac00000`、`adsp_fw_region@92a00000`、`pil_mba_region@94a00000`、`cdsp_fw_region@94c00000` | 活动 DT 摘要列出相同名称、unit-address 和 removed-dma-pool 集合 | **精确**（名称/基址/类别） | 属最小 DTS 的关键内存约束候选；仍需从完整 DT 或原厂 DTB 导出逐区 `reg`/`no-map` 后才可定稿。部分尺寸含 vendor 修改，不能当纯 SoC 常量。 |
| dynamic reserved-memory | `venus_fw_region`、`adsp_region`、`qseecom_region`、`secure_region`、`linux,cma` | 活动 DT 记录相同 shared-dma-pool 名称与 size：8MiB、8MiB、20MiB、92MiB、44MiB | **精确** | 可作内存布局约束，不自动代表每个 Android DSP/QSEE pool 都应被主线驱动保留。不可侵占 fixed no-map 区。 |
| ramoops/pstore | 当前下载 DTS/include 未见 ramoops | 实机活动 DT 与 `/sys/fs/pstore` 均未显示该节点/记录 | **未验证（负证据）** | 不得声称下游已有 ramoops；未来需在完整内存图与上游 binding 下另行设计。 |
| UART | SoC/MTP include 涉及 `c170000`、`c16f000`、`c1af000`、`c1b0000`；17011 顶层未见 UART 专属覆写 | 实机只有 `uart@c1af000` 为 `ok`，其余 disabled；bootargs 却有 `earlycon=...0xc170000` 和 `printk.disable_uart=1` | **精确**（节点状态）；**未验证**（console 实际映射、pinmux、物理可达） | 坚持 USB-first。不得据 MTP include 或 bootargs 直接启用 UART；早期调试需另行取证 aliases、pinmux 与物理线路。 |

## 结论

1. 活动 DWC3/QUSB2 实证支持 **USB2 high-speed gadget-first**。`a800000.dwc3` 已经在实机 `configured`，而 SuperSpeed PHY 方向在活动下游树中被禁用。
2. eMMC 控制器与主要 reserved-memory 布局有明确的实机地址锚点，但供电、pinctrl、时序和所有 `no-map` 细节仍不能从 MTP include 直接继承。
3. `sdm660-mtp.dtsi` 是 Qualcomm 基础参考层。对 USB/eMMC/UART 的 status、GPIO、regulator 和 pinctrl，只有实机活动 DT 或未来原厂 DTB/固件逐项验证后才能升级为 R11s 板级事实。
4. 未取得经 hash 校验的匹配原厂固件前，不生成、构建、打包或测试任何 R11s 镜像。

## 相关证据

- `recon/third_party_r11s_source_evidence_20260730_051654/color597_kernel_17011/sdm660-pm660a-mtp-17011.dts`
- `recon/third_party_r11s_source_evidence_20260730_051654/color597_kernel_17011/sdm660-mtp.dtsi`
- `recon/third_party_r11s_source_evidence_20260730_051654/color597_kernel_17011/sdm660.dtsi`
- `recon/p0_adb_readonly_20260730_033057/device_tree_live/ssusb_a800000.txt`
- `recon/p0_adb_readonly_20260730_033057/device_tree_live/hsusb_c200000.txt`
- `recon/p0_adb_readonly_20260730_033057/device_tree_live/usb_pmic_reserved.txt`
- `recon/p0_adb_readonly_20260730_033057/device_tree_live/reserved_uart_emmc_boardid.txt`
