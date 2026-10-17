# Oppo R11s 原厂固件获取与主机只读解包取证报告

**取证日期：2026-07-30**  
**采集方式：** 历史只读网络调研与本地只读取证；2026-07-30 已从用户提供的 ColorOS CDN URL 下载并校验 C.19 `.ozip` 原始容器。未解密或提取 payload；仅读取容器头部明文元数据；未操作设备。  
**目标设备：** OPPO R11s，Qualcomm SDM660，arm64，PM660/PM660L，eMMC。序列号 9144dacf。设备当前已被 DotOS 覆盖，原厂镜像必须从官方固件包获取。

---

## 1. 官方固件分发渠道与原厂版本

> **2026-07-30 增补（用户确认的官方 C.19 / 已核验的官方 CDN 容器）：** 用户提供的 `coloroswebsitefs.coloros.com` URL 成功以 HTTP Range 响应下载 `R11s_11_OTA_1190_all_Vv6yB9efD2ry.ozip`。CDN 响应元数据给出对象长度 `2,618,885,608` 和 `x-amz-meta-content-md5=e9aee976b7c4559ae4ca977b727ef117`；本地原始容器同长度，MD5 相同，SHA-256 为 `a65deb2681255d7e16e0a98a11843ebcb31378d722b5687fd835161902b6ac73`。用户随后明确确认该 C.19 为官方固件。项目据此将该原始容器来源标为“用户确认的官方固件 + 官方 CDN 对象一致性”；这**不等同于**已解密/审计包内 payload、已验证签名链、已验证回滚兼容性或已验证实机安装条件。

- **官方渠道**：OPPO 官方主要通过 `support.oppo.com/<区域>/software-update` 与 `oppo.com/en/rom`（ColorOS Assistant / 系统升级工具）提供固件入口。当前在线分发主要面向 ColorOS 11+ 设备；R11s 出厂为 ColorOS 3.2，已超出官方在线推送周期。  
  【来源: https://support.oppo.com/my/software-update ；https://www.oppo.com/en/rom 】【可信度: 官方一手，仅说明当前分发机制，不保证 R11s 仍在线】
- **C.19 包元数据（官方 CDN 原始容器头，已读取）**：`pre-device=R11s`、`version_name=R11s_11_C.19`、`ota_version=R11s_11.C.19_1190_202010310009`、`google_patch=20200905`、`ota-type=BLOCK`。这些是 `.ozip` 包头可见的内部声明；它们与下载对象身份共同构成强来源/版本证据，但不替代对加密 payload、签名链、分区内容或兼容性的后续只读审计。
- **固件包命名与扩展名（已证实）**：国际版固件包形如 `CPH1719EX_11_A.xx_YYYYMMDD_*.rar`，约 2.6–2.7GB；OTA 增量包为 `.ozip`；线刷包（QPST/MSM Download Tool 格式）后缀 `.ofp` 或 QPST rar。  
  【来源: https://azrom.net/stock-rom-oppo-r11s-cph1719-r11st-r11s-plus-cph1721-all-file-repair ；https://firmwarefile.com/oppo-r11s-cph1719 ；https://repairmymobile.co/flash/oppo-r11s-cph1719-flash-file 】【可信度: 可信二手（第三方固件站收录，文件名与 OPPO 官方命名规则一致；非 OPPO 官网直链）】
- **关键区分**：CPH1719 是 R11s 国际版；CPH1721 是 R11s Plus（不同设备）；中国大陆存在公开版 R11s（无 t）与中国移动定制版 R11st。用户已确认、且本机 `ro.product.model` 佐证目标为 **R11s（无 t、中国大陆公开版）**；取证必须按此精确型号匹配，不得混用 R11/R11s Plus/R11st 的 boot 或其他分区镜像。
- **可信下载渠道评价**：azrom.net / firmwarefile.com / repairmymobile.co / givemerom.com / needrom.com 均为第三方固件聚合站，非 OPPO 官方。文件名与官方命名一致，可作取证参考，但**不能视为经哈希校验的一手来源**——下载后必须与 OPPO 官方渠道（客服、官方授权售后）提供的哈希或 OPPO 官方服务器上同版本文件交叉核对。  
  【可信度: 第三方镜像，未证实完整性】
- **建议的一手获取路径（待现场验证）**：联系 OPPO 官方客服/售后索取 CPH1719EX_11_A.22（或最新版）官方固件包与哈希；或通过 OPPO 官方"手机助手/系统升级工具"从官方服务器拉取。拿到官方源 URL 或哈希前，任何第三方镜像只算"待验证"。

## 2. OPPO OFP 固件包在 Linux 主机的只读解包工具

- **OFP 格式**：OPPO Qualcomm 线刷包（.ofp）是 OPPO 自定义容器；其具体加密方式、内含分区与分区镜像形式因包而异，须对目标 R11s 原厂包只读解包后确认。
- **工具 1：bkerler/oppo_decrypt**（GitHub，GPL，Python3）。`ofp_qc_decrypt.py` 专用于 Qualcomm 平台 OPPO .ofp；`ofp_mtk_decrypt.py` 用于 MTK。**R11s 是 SDM660，必须用 qc 版**。用法：`python3 ofp_qc_decrypt.py [file.ofp] [outdir]`。  
  【来源: https://github.com/bkerler/oppo_decrypt 】【可信度: 可信二手（开源、可审计源码，社区广泛引用）】
- **工具 2：italoalmeida0/OppoRealme-OFP-Flash**（GPL-3.0）。含解包/合并逻辑与 `simg2img`；本项目红线禁止刷写，仅用其解包部分。  
  【来源: https://github.com/italoalmeida0/OppoRealme-OFP-Flash 】【可信度: 可信二手（开源）】
- **OTA `.ozip` 容器边界**：已下载的 C.19 原始对象以 `OPPOENCRYPT!` 开头，普通 ZIP 工具不能直接解开加密 payload；其加密 payload 区域和尾部对象目录均尚未解析。其头部声明封装内长度为 `2618881432`。因此，当前不能声称该包含有或不含 `system`、`vendor`、`firmware-update`、`boot.img`、`recovery.img`、`vbmeta.img` 或 `dtbo.img`；任何清单、签名链或 payload 完整性结论均须来自后续单独授权的主机侧只读解密/解析。
- **工具 3：vm03/payload_dumper**（Python3，开源，1.8k stars）。从 A/B OTA `payload.bin` 提取 boot/dtbo/system/vendor。  
  【来源: https://github.com/vm03/payload_dumper 】【可信度: 可信二手（开源、广泛使用）】
- **工具 4：ssut/payload-dumper-go**（Go，开源）。二进制易部署。  
  【来源: https://github.com/ssut/payload-dumper-go 】【可信度: 可信二手】
- **工具 5：manojanasuri16/payload_dumper**（Python3，活跃 fork，支持 `--list`/`--partitions` 选择性提取，便于只读取证 boot/dtbo）。  
  【来源: https://github.com/manojanasuri16/payload_dumper 】【可信度: 可信二手】
- **Android boot image header 解析**：解出 `boot.img` 后用 `abootimg -x boot.img` 或 `mkbootimg/unpackbootimg` 拆 header/kernel/ramdisk。`abootimg` 在 Debian/Ubuntu 可装。  
  【来源: XDA 指南 https://xdaforums.com/t/guide-how-to-build-kernel-from-source.2192805 】【可信度: 可信二手】
- **simg2img**：合并 sparse 分区镜像为单文件，`sudo apt install android-tools-fsutils`。  
  【可信度: 官方一手（Android SDK 工具）】

## 3. R11s 官方开源 kernel 仓库

- **OPPO 官方开源组织**：GitHub `oppo-source`（邮箱 <EMAIL>），173 个仓库，按 SoC 命名如 `android_kernel_oppo_sm8550`、`android_kernel_oppo_mt6771` 等。  
  【来源: https://github.com/oppo-source 】【可信度: 官方一手（OPPO 官方开源账号）】
- **是否含 SDM660/R11s 仓库**：检索中**未见** `android_kernel_oppo_sdm660` 或以 R11/R11s 命名的仓库。现有 SoC 仓库集中在 sm845/sm8550/sm7325/sm6125/sm7150/mt6833/mt6765/mt6771/mt6983 等，无 sdm660 条目。  
  【来源: https://github.com/oppo-source 】【可信度: 官方一手，负证据——当前不可核对，不代表历史上没有】
- **第三方自称 R11s 内核源**：`color597/android_kernel_oppo_sdm660-9`，README 声称 "ColorOS Linux kernel source code for OPPO R11/R11s series"，但仅 1 commit，无 release/tag，无可核对来源链，不能视为 OPPO 官方一手。  
  【来源: https://github.com/color597/android_kernel_oppo_sdm660-9 】【可信度: 未证实（第三方转载，非官方账号，无校验）】
- **open.oppomobile.com**：OPPO 历史开源合规页。本次环境未能直接访问验证其当前是否仍托管 R11s 源码。  
  【可信度: 未证实】
- **结论**：**未证实** OPPO 为 R11s/SDM660 发布过可核对的官方 kernel 仓库。建议人工访问 `open.oppomobile.com` 搜索 "R11s"/"CPH1719"/"sdm660" 并截图存档；若无，依据 GPLv2 向 OPPO（<EMAIL>）书面索取 CPH1719 对应内核源码。

## 4. R11s 固件内 boot/recovery/dtbo 形式

- **boot image header 版本**：Android 版本不能单独证明 R11s 原厂 boot header 版本；须在取得匹配原厂 `boot.img` 后，从其实际 header 只读解析确认。
- **DTBO 分区**：实机 ADB by-name 分区表（69 个分区）未见 `dtbo` 符号链接；fastboot 的 `partition-type:dtbo` 与 `partition-size:dtbo` 均返回 `Variable Not found`。本设备布局是否存在 dtbo 分区尚未证实，现有两路一手证据均未出现它。
- **AVB / vbmeta**：实机分区表存在 `vbmeta`，但 AVB 是否实际启用、版本、覆盖的分区及验证策略均待匹配原厂镜像只读解包确认。

## 5. 下载后应记录的元数据/hash

作为可回滚的原厂材料（存 `backups/factory/`），每个文件须记录：

1. 设备精确型号：OPPO R11s（无 t、中国大陆公开版），已由用户确认，并经 `ro.product.model=OPPO R11s` 佐证。
2. 固件版本号：如 `CPH1719EX_11_A.22_190702`（地区 EX=国际）。
3. Android / ColorOS 版本：Android 7.1.1 / ColorOS 3.2（国际版）。
4. SoC / PMIC：Qualcomm SDM660，PM660+PM660L（已证实）。
5. 获取方式与来源 URL：官方/第三方镜像 URL、下载日期、是否经 OPPO 官方哈希核对。
6. SHA-256：对原始整包；解包后对实际出现的 `boot.img`、`recovery.img`、`vbmeta.img`、`system.img`、`vendor.img` 等分区镜像分别计算。`dtbo.img` 仅在实际出现时记录。
7. 文件大小：原始包与各分区镜像字节数。
8. 解包工具与版本：记录所用 `oppo_decrypt` commit、`payload_dumper` 版本，确保可复现。
9. boot image header 版本、cmdline、kernel/ramdisk 偏移（解包后从 header 读取）。
10. AVB 标志：vbmeta 是否存在、AVB 版本、验证 key 链（只读，不提取私钥）。
11. 分区表 dump：`by-name` 链接列表与大小（与用户已有 ADB 取证交叉核对）。
12. README：写入 `backups/factory/<固件版本>/README.md`，含上述全部字段与获取人/日期。

## 6. 已证实 vs 待现场验证

- **已证实**：目标为 R11s（无 t、中国大陆公开版）；SDM660；实机分区表含 boot/recovery/vbmeta；`dtbo` 在 ADB by-name 与 fastboot getvar 中均未出现；解包工具链可供主机侧只读审计。
- **待验证**：①官方历史 ROM 页面/官方发布记录与该 CDN 对象之间的可直接网页回链（2026-07-30 本轮 Tavily MCP 已恢复，但其 OPPO/ColorOS 官方域名结果仅返回现行通用支持/升级页，未返回 R11s 或 C.19 的一手条目）；②`open.oppomobile.com` 是否有 R11s/sdm660 内核源；③容器内原厂 boot header 实际版本；④AVB/vbmeta 实际版本与策略；⑤原厂包实际分区清单是否包含 `dtbo`。

## 7. 红线遵守

- 全程只研究"固件包从哪合法获取 + 如何在 Linux 主机只读解包"，未涉及 EDL/9008 认证绕过、解锁工具、刷写或写分区方法。
- 严格区分 R11s（CPH1719）与 R11/R11s Plus/R11st；未将任何 MTK/MT6572 内容作为 R11s 依据；`ofp_mtk_decrypt.py` 仅作工具说明，R11s 必须用 `ofp_qc_decrypt.py`。
- 每条结论均附来源 URL 与可信度标注；无原始 URL 的搜索结论已标为未证实。
