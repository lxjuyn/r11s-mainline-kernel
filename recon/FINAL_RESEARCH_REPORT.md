# R11s 调研审计与证据状态

**状态：仅主机侧文档审计；未操作手机。**  
**审计日期：2026-07-30**  
**项目边界：**不解锁、不写分区、不刷写、不生成可刷镜像；Qualcomm 9008/EDL 仅作为原厂恢复路径，绝不用于自定义固件或绕过签名/认证。

## 1. 本轮 workflow 处置

旧的深度调研 workflow `wf_b1d9d39b-0f6` 启动了 24 个任务，但大量任务长期没有回传，已不应继续等待。此前的汇总 workflow 还混入了 `/home/<user>/claude/6572` 的 MTK/Z1 本地资料，因平台不相同，已停止且其相关结论不纳入 R11s 证据。

本轮改为三个更小的只读核验范围：

1. R11s 身份、型号和可用下游源码；
2. SDM660 上游 DTS 与 DWC3/QUSB2 USB 基础；
3. USB gadget、ramoops 与启动安全门禁。

其中后两项虽然给出了有价值的**通用上游架构**，但其网页检索额度耗尽，部分外部 URL 未能现场读取；因此不能把其具体型号、寄存器、DTS 路径或 bootloader 能力视为已经独立证实的 R11s 事实。

补充核验发现：一项 agent 输出把 Redmi Note 7 Pro / SM6125 错认作本项目的 Oppo R11s；另一项将 MT6572 的 MUSB/LK 资料用于 R11s fastboot 推断。两者均为平台污染，已排除。下文的通用 USB/ramoops 结论只保留不依赖这些错误前提的部分。

## 2. 已确认的项目事实

以下仅包含用户明确给出的事实或项目边界：

- 项目目标是对手上 Oppo R11s 进行主线 Linux / Ubuntu arm64 的可行性调研；
- 设备可以解锁；
- 设备能够进入 Qualcomm 9008/EDL；
- 9008 不可用于刷写自定义固件，因此仅保留为原厂恢复/救援后路；
- 物理 TTL/UART 难以引出，优先研究手机作为 USB gadget 的后期调试通道；
- 当前工作限于调查和文档，不操作设备。

## 3. 可采纳的通用技术结论（不是 R11s 板级事实）

### 3.1 USB gadget 不是早期 UART 的替代品

主线 USB gadget 的正常链路是：DWC3/PHY/时钟/复位/供电和设备树匹配成功 → UDC 注册 → 用户态 configfs 创建 CDC ACM 或 ECM/NCM function → 绑定 UDC → PC 枚举。

因此 CDC ACM 可在成功进入用户态后提供 `/dev/ttyACM*`（PC 端）一类通道，ECM/NCM 可进一步提供 USB 网络；但它不能诊断 DWC3/PHY probe 之前、页表/GIC/早期内核阶段的崩溃。该结论来自内核 USB gadget 文档，适用于一般 Linux gadget 架构，**不证明 R11s 的 DWC3、PHY、connector、供电或角色检测已正确取证**。

参考：

- https://www.kernel.org/doc/html/latest/usb/configfs_gadget.html
- https://www.kernel.org/doc/html/latest/usb/gadget_configfs.html
- https://www.kernel.org/doc/html/latest/usb/gadget.html

### 3.2 ramoops/pstore 需要真实、非重叠的保留内存

ramoops 需要以设备树 `reserved-memory` 或等价的平台机制明确保留连续物理内存；地址、大小和与 modem/DSP/TEE 等保留区的关系必须由 R11s 原厂 DTB/DTBO、下游 DTS 或实机只读内存布局确认。不能从任何其它手机复制数值。

参考：

- https://www.kernel.org/doc/html/latest/admin-guide/ramoops.html
- https://www.kernel.org/doc/html/latest/admin-guide/sysctl/pstore.html
- https://www.kernel.org/doc/html/latest/core-api/pstore.html

### 3.3 SDM660 级别的上游参考只能证明 SoC 起点

主线资料中出现 `sdm660.dtsi`、`sdm630.dtsi` 和同 SoC 参考板 DTS 是合理的调研起点。它们可帮助定位通用时钟、TLMM、SPMI、SDHCI、DWC3/QUSB2 等子系统，但**绝不能**代替 R11s 的：PMIC、regulator、eMMC 参数、reserved-memory、USB PHY 供电、USB 角色检测、面板或 pinctrl 证据。

候选上游入口（后续须在网络恢复后逐条现场验证）：

- https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm64/boot/dts/qcom/
- https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/usb/dwc3/
- https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/phy/qualcomm/

## 4. 明确排除的内容

以下不得写进 R11s DTS、启动设计或事实表：

- MT6572/Z1 的 Preloader、LK、ATAG、appended DTB、MTK boot header、`mkbootimg --mtk`、WDT、ramdisk、分区名或 C3 UART 参数；
- 把 R11、R11s、R11s Plus 或任意 OPPO 地区变体互换；
- 没有原始 URL/文件 hash/源码路径或镜像偏移的 agent 搜索结论；
- 关于 R11s `fastboot boot`、boot image header、AVB 版本、DTBO、PMIC 型号、DWC3 节点、EDL 认证状态的推测；
- 先前工作流声称 R11s 是 MTK 或将 MTK 资料用于 R11s 的结果。

## 5. 当前无法确认、必须后续只读取证的事项

| 事项 | 可接受的证据 | 当前状态 |
|---|---|---|
| 精确商品型号、地区变体、ColorOS build | 关于页面/只读 ADB 属性/官方固件 metadata | 未取证 |
| SoC、PMIC、eMMC 与面板/触摸硬件 | 原厂 DTS/DTB、下游 kernel、拆机或只读系统资料 | 未取证 |
| Oppo R11s OSS kernel/DTS/defconfig | 官方开源仓库中的版本/commit/文件 hash | 未取证 |
| boot/recovery/dtbo/分区表 | 原厂包或用户保留材料的 SHA-256、解包清单 | 未取证 |
| boot image header、cmdline、AVB/签名关系 | 原厂 boot 镜像解析记录 | 未取证 |
| 标准 fastboot 是否存在、`fastboot boot` 是否支持 | 实机只读协议能力与明确的 bootloader 响应 | 未取证 |
| DWC3/PHY/regulator/role 与 connector 线路 | R11s 原厂 DTB/DTBO 或下游 DTS 节点 | 未取证 |
| ramoops 可用物理地址/大小 | R11s reserved-memory 映射 | 未取证 |

> `fastboot getvar all` 可以作为未来的**只读信息采集**候选，但其可用键和值均由 OEM bootloader 决定。不存在通用 `flashable:boot=yes` 响应即可证明 `fastboot boot` 成功的规则；只有该机实测的 `fastboot boot` 协议行为、且在当次得到用户许可后，才可断定它是否支持临时启动。

## 6. Ubuntu 的首个成功目标

最小成功目标不是完整桌面，而是：主线内核进入稳定 userspace，并在 UDC 起来后通过 CDC ACM 或 ECM/NCM 获得 shell/日志。最初可采用一个最小 initramfs 以减少对 eMMC、分区和完整 Ubuntu Base 的依赖；Ubuntu Base/完整 rootfs 则应等存储、调试通道和可回滚启动方式都有证据后再考虑。

这只是后续设计边界，不构成构建或镜像制作授权。

## 7. 下一阶段的唯一合格输入

后续若继续调查，优先补齐下列**只读原始材料**：

1. 精确 R11s 型号、区域和固件 build；
2. 对应官方固件/开源 kernel 的可验证来源；
3. 原厂 boot、recovery、dtbo（如存在）和分区表的合法本地副本及 SHA-256；
4. R11s DTB/DTBO 解码后的 USB、存储、PMIC、reserved-memory 节点；
5. bootloader 公开的只读信息。

没有这些材料，项目保持“调研完成但板级实现不可启动”的状态；不以参考手机或网络猜测推进到构建、打包或设备测试。
