# R11s 状态概述 + 双面板兼容性差距清单

> 生成：2026-09-01 · 执行方式：`AGENT_ORCHESTRATION.md` SOP（Wave A 本地取证 → Wave B/C 联网取证 → Wave D 汇总）
> 证据约定：本地结论附 `路径:行号`；联网结论标注 `[联网·佐证级]`，不作唯一依据。
> 账本：`recon/orchestration/LEDGER_dualpanel_20260901.md`

---

## 一、结构化状态概述

### 1.1 项目基线

| 项 | 值 | 复核 |
|---|---|---|
| 设备 | OPPO R11s（17011，SDM660）serial 9144dacf | — |
| 内核树 | `out/linux-sdm660-oppor11-t-qcom-sdm660-7.0.y`（Linux 7.0.14，分支 main，已推送） | — |
| 构建目录 | `build/r11s_phase2`，vermagic `7.0.14-sdm660-gcc++` | — |
| 实刷版本 | **v13**（`panel-regdiag`） | sha256 `0d2966a1…fbc02092` ✓（15,106,048 B） |
| 回滚终极件 | `boot-debug.img` | sha256 `4ff811c3…e08d1a7a4` ✓（20,717,568 B） |
| rootfs v3 | `out/r11s_phase4a_rootfs_v3.ext4` | sha256 `f54772b7…12d606b` ✓（201,326,592 B） |
| 归档总数 | `backups/products/` 共 **56** 个归档目录 | 实点 |
| 设备当前态 | 运行 v13 救援 shell（非 fastboot），gadget = ttyACM0 | HANDOFF §五 |

### 1.2 已完成功能模块

| 域 | 状态 | 关键证据 |
|---|---|---|
| **取证与门禁** | ✅ 完成 | OZIP 解密、9 DTB 取证（board-id 0x4273=17011）；ABL 解压门禁 ≥0x3180000 被拒；`fastboot boot` 实测不支持 |
| **启动链** | ✅ 完成 | 阶段 1（dtbsurg）PASS、阶段 2 v2 PASS；唯一开发路径 = `fastboot flash boot` |
| **内核与构建** | ✅ 完成 | 本地重编 7.0.14，782→681 模块，defconfig 966 行最小集，三条提交已推送 |
| **显示（本台）** | ✅ **打通** | v13：OLEDB 3.40s → sofeg01_s 3.75s probe（power mode 0x9e）→ fbcon/fb0 3.86–3.95s；`devices_deferred` 为空 |
| **面板驱动（双）** | ✅ **均已内置内核** | 见 §2.1 |
| **触摸** | ⚠️ 半通 | I2C/中断链路 OK，用户划屏产生真实中断；**F12 描述符读不出（I2C -95）**，坐标不出 |
| **音频** | ❌ 未开始 | 声卡 `sdm660-int-sndcard` defer + `152c000.audio-codec` defer；机器驱动未写 |
| **WiFi / BT** | ❌ 未验证 | ath10k snoc config 已开；固件在 rootfs 就位但未上板 |
| **电池 / 充电** | ✅ 完成 | `qcom_smbx` 限流（4.8A 上限已修复）、DTB battery@4000 已开 |
| **rootfs / userland** | ✅ 主机侧就绪 | v3 = Alpine + 681 模块 + 110 固件 + WiFi 四件套（rmtfs/pd-mapper/qrtr-*） |
| **切根（阶段 4）** | ⏸ 待授权 | v10 镜像就绪但基于 v9 内核；p69 未格式化 |

### 1.3 正在进行 / 待解决（按优先级）

| # | 事项 | 级别 | 说明 |
|---|---|---|---|
| 1 | **v14 合成**（v13 内核 + v10 切根 init） | 高 | v10 现基于 v9，直接刷会丢显示链修复；需重打包并加 `deferred_probe_timeout=30` |
| 2 | 格式化 p69 + 写 rootfs v3 | 高 | 需用户当次确认，脚本双重确认 |
| 3 | **触摸 F12 描述符**（I2C -95） | 高 | 唯一故障点，v8 已排除中断/供电/链路 |
| 4 | **GPU 固件缺失** `qcom/a530_pm4.fw` | 中 | 实测固件清单中**不存在**该文件（见 §3.3） |
| 5 | 音频机器驱动 | 中 | 上游有在途补丁（见 §3.2） |
| 6 | WiFi 上板 / BT 固件名核对 | 中 | `qca/crbtfw21.tlv` 已在固件清单（113,976 B） |
| 7 | DPU `mdp_clk_src` RCG warning | 低 | 不阻塞 fbcon |
| 8 | v12 竞态复验 | 低 | 科学性验证，建议跳过 |

---

## 二、双面板兼容性：现状矩阵与差距清单

### 2.1 现状矩阵（两块面板逐项对比）

| 项 | SOFEG01_S | AMS596W401 | 差异 |
|---|---|---|---|
| 驱动文件 | `panel-samsung-sofeg01-s.c`（504 行） | `panel-samsung-ams596w401.c`（554 行） | — |
| compatible | `samsung,sofeg01-s`（:488） | `samsung,ams596w401`（:538） | 各唯一、互斥 |
| Kconfig | `DRM_PANEL_SAMSUNG_SOFEG01_S`（Kconfig:845） | `DRM_PANEL_SAMSUNG_AMS596W401`（Kconfig:855） | 依赖同为 OF + DRM_MIPI_DSI + BACKLIGHT_CLASS_DEVICE |
| defconfig | `r11s_defconfig:494` = **y** | `r11s_defconfig:495` = **y** | 一致 |
| 构建 .config | `.config:4094` = **y** | `.config:4095` = **y** | 一致 |
| 编译产物 | `panel-samsung-sofeg01-s.o`（311.76 KB，built-in） | `panel-samsung-ams596w401.o`（312.47 KB，built-in） | 均内置（`modules.builtin:216-217`） |
| 分辨率 | **1080×2160**（:335/:339） | **1080×2280**（:373/:377） | ⚠️ 不同 |
| 物理尺寸 | 68×136 mm（:343-344） | 68×144 mm（:381-382） | ⚠️ 不同 |
| 时序 | hfp112/hbp96/hsw20；vfp20/vbp4/vsw2（:334-341） | hfp80/hbp52/hsw20；vfp20/vbp16/vsw2（:372-379） | ⚠️ 不同 |
| 供电 | vddio/vdd/oledb（:49-53） | vddio/vdd/oledb（:58-62） | 完全一致 |
| reset GPIO | `reset-gpios = <0x28 0x35 0x00>`（TLMM 53） | 同左（:2357） | **共用** |
| 供电 phandle | 0x5f / 0x60 / 0x61 | 0x5f / 0x60 / 0x61（:2358-2360） | **共用** |
| reset 时序 | 高5ms→低2ms→高12ms | 同左 | 一致 |
| 背光 | 16-bit DCS，max 1023，初始 512 | 同左 | 一致 |
| DTB status | **无 status 属性 = okay** | `status = "disabled"`（:2355） | 编译期选择 |
| port/endpoint | **有**（:2344-2350，↔ dsi endpoint 0x66/0x5e） | **无** | ⚠️ 关键缺口 |
| 运行时探测 | `mipi_dsi_dcs_read(0x0a)`（:256） | `mipi_dsi_dcs_read(0x0a)`（:264） | ⚠️ 同为读 Power Mode，**非变体 ID** |

> 证据基底：`backups/source/dtb_v12_surgery_20260830_063453/dtb_v12.verify.dts:2333-2364`（v12/v13 实刷 DTB 反编译原文）

### 2.2 核心结论

**当前"双面板兼容"实际是「双驱动 + 单 DTB 编译期开关」，不是运行时自动识别。**
两块面板的驱动都已编进内核，但任一时刻只有 `status="okay"` 的那个能 probe；选择发生在**打包 DTB 时**，不在机器上。

---

### 2.3 差距清单

| ID | 差距 | 现状 → 目标 | 依据 | 动作 | 阻塞级 |
|---|---|---|---|---|---|
| **G01** | **无运行时变体探测** | 两驱动 probe 均只读 DCS 0x0A（Get Power Mode），不读 ID 寄存器（0x04/0xDA/0xDB）→ 需能区分两块屏 | `sofeg01-s.c:256`、`ams596w401.c:264` | 路线 A（低成本）：维持双 DTB，按变体刷对应 DTB；路线 B（真兼容）：实现 ID 探测 + 统一驱动或 host 侧 fallback | 🔴 高（若目标为"单镜像通吃"） |
| **G02** | **panel@1 缺 port/endpoint** | panel@0 有 port（:2344-2350），panel@1 无 → enable 后无法与 DSI host 绑定 | `dtb_v12.verify.dts:2344-2350` vs `:2353-2364` | 走路线 A 必补：给 panel@1 加 port/endpoint，并同步 `remote-endpoint` 指向 dsi endpoint | 🔴 高（路线 A 必需） |
| **G03** | **共用 reset GPIO 与供电组** | 两者 reset-gpios 同 0x28 0x35 0x00，供电 phandle 同 0x5f/0x60/0x61，pinctrl 同 default/sleep | `:2336-2342` vs `:2357-2363` | 硬约束：任一时刻**只能一个** panel `okay`；否则 GPIO/供电争抢。需在 DTB 检查脚本中加断言 | 🟡 中 |
| **G04** | **ams596w401 的 mode/时序未实机验证** | 1080×2280 与时序均为原厂 dtsi 转录，本机从未点亮过 | `ams596w401.c:372-382` | 先定案本机变体（见 G05）；若需支持 2280，必须找一台该变体实机验证 | 🔴 高（决定支持范围） |
| **G05** | **本机变体虽已实锤，但目标需明确** | v13 实机 sofeg01_s probe 成功（power mode 0x9e）→ **本机是 SOFEG01_S（1080×2160）** | v13 归档 `README.md` + `v13_dmesg_dedup.txt` | 决策：本台够用（则双面板 = 技术储备）or 通用镜像（则必须做 G01 路线 B + G04） | 🟣 决策项 |
| **G06** | **ams596w401 的 ESD 期望值未知** | 原厂 sofeg01_s：读 0x0a 期望 0x9e；ams596w401 的 `panel-status-value` 未取到 | `R11S_PANEL_FORENSICS_20260829.md` §1 | 从 `android_kernel_oppo_sdm660_source_…/dsi-panel-oppo17011samsung_ams596w401_1080_2280_cmd.dtsi` 转录 | 🟡 中 |
| **G07** | **树内 R11s DTS 完全没有显示节点** | `sdm660-oppo-r11s.dts`（212 行）grep `mdss\|dsi\|panel` **0 命中**；继承的 mdss/dsi0/dsi1 全 `disabled` | `.sdm660-oppo-r11s.dtb.dts.tmp:1630-1656(mdss disabled)、:1732-1770(dsi0 disabled)、:3045-3119(dsi1 disabled)` | 显示链 100% 依赖"手术 DTB"，与主线 DTS 脱节 → 把显示链节点回写进树内 DTS | 🔴 高（技术债，且阻塞 G01/G02 主线化） |
| **G08** | **两驱动 Kconfig 未声明 GPIOLIB** | depends 仅 OF + DRM_MIPI_DSI + BACKLIGHT_CLASS_DEVICE，但 probe 要 `devm_gpiod_get("reset")` | Kconfig:845-864；`sofeg01-s.c:434-437` | 补 `depends on GPIOLIB`（或确认由 DRM_PANEL 链隐式保证） | 🟢 低（顺手项） |
| **G09** | **树内 DTS 与实刷 DTB 双轨** | 实刷 DTB 来自下游 17011 改造，树内 DTS 是另一套 → 改面板必须动 DTB 二进制 | L3 取证 | 同 G07；合并为单一来源 | 🟡 中 |

### 2.4 建议路线（按成本排序）

- **最小成本（推荐先做）**：接受本机 = SOFEG01_S 已定案，双驱动常驻内核作冗余；同时补 **G02**（给 panel@1 补 port）+ **G03**（加单 okay 断言），产出「双 DTB」：`dtb_sofeg01.dtb` / `dtb_ams596.dtb`，按批次刷对应件。
- **中期**：做 **G07/G09**，把显示链回写进树内 R11s DTS，结束双轨。
- **真·单镜像通吃**：G01 路线 B（ID 探测）+ G04（需 2280 变体实机）+ G06（ESD 值）三件齐备才可能，成本最高。

---

## 三、联网依赖、取证结果与降级

### 3.1 哪些结论依赖联网（及本地一手替代）

| 结论需求 | 联网必要性 | 本地一手替代（更强的证据） | 本次结果 |
|---|---|---|---|
| 面板硬件身份 / driver IC 型号 | 仅佐证 | 原厂 DTS/DTB 取证已完成（`r11s..dts:16292-16369`） | ⚠️ 未取到有效公开资料 → 降级 |
| 主线多面板变体处理惯例 | 强依赖 | 树内 DTB 现状分析（已完成，已足够定案） | ⚠️ 无有效结果 → 降级 |
| SDM660 声卡上游状态 | 强依赖 | 树内是否有 `sdm660-internal.c` | ✅ 部分成功（见 §3.2） |
| SDM660 外设总体现状 | 中 | 实机 dmesg + 固件清单 | ❌ 被反爬拦截 → 降级 |
| sofeg01 家族跨机型佐证 | 仅佐证 | 项目内 `android_kernel_oppo_sdm660_source_d9391f88aa90/` | ❌ 超时 → 降级 |

### 3.2 联网取证成果（唯一实质收获）

**[PATCH v4 00/15] SDM660 sound card and WCD codecs over internal MI2S** `[联网·佐证级]`

- v1：2026-02-10，Richard Acayan，10 补丁，新增 `sound/soc/qcom/sdm660-internal.c`（271 行），
  配套 q6dsp internal MI2S、PM660L analog-codec compatible、msm8916 digital-codec 加 SDM660 compatible、
  `qcom,sm8250` binding 加 `sdm660-internal`。用于 Redmi Note 7 与 Pixel 3a。
  来源：`lwn.net/Articles/1058301`（一手：LKML 原文转发）
- v4：2026-05，扩为 **15 补丁**，覆盖 SDM660 声卡 + WCD codecs over internal MI2S。
  来源：`ratatoskr.run/linux-arm-msm/2026/05/8251534`
- **合入状态未证实**（未找到 merge 确认或目标内核版本）→ 记为「未取证」。
- 对本项目的意义：与待办 #5（音频机器驱动）直接相关。若补丁尚未合入 7.0.14，需自行移植或写机器驱动；
  **下一步应先在树内 grep `sdm660-internal` 确认是否已存在**。

### 3.3 联网失败的连带发现（本地取证补位）

固件清单实测（`backups/firmware_inventory_r11s_20260830_043151/`）：

| 固件 | 存在 | 大小 |
|---|---|---|
| `firmware/qcom/sdm660/adsp.mdt` | ✅ | 7,964 B |
| `firmware/qcom/sdm660/cdsp.mdt` | ✅ | 7,068 B |
| `firmware/qca/crbtfw21.tlv` | ✅ | 113,976 B |
| **`qcom/a530_pm4.fw`** | ❌ **缺失** | — |

→ 印证 HANDOFF 待办 #3：GPU 固件在 110 文件清单中**确实不存在**，fbcon 不受影响但 GPU 加速不可用。

### 3.4 降级策略（已执行）

| 级别 | 触发 | 处置 | 本次实例 |
|---|---|---|---|
| L0 | 某项「未找到」 | 标"未取证"，非阻塞 | §3.1 五个降级项 |
| L1 | 偏离输出契约 | 收紧契约重派 1 次 | 未触发 |
| L2 | 超时 / abort | **不重派原任务**，拆小重派 | C1 拆小重搜；C3 改为搜索摘要替代页面抓取 |
| L3 | 连续 2 次失败 | Hub 亲自兜底 / 标记未取证 | C1/C3 → 标记未取证；**L4 归档盘点子代理 abort → Hub 兜底完成（hash 全部复核通过）** |
| L4 | blocking 项走到 L3 | 停下请求裁决 | 未触发（联网项均非阻塞） |

**总原则**：联网结论一律为**佐证级**，不得作为唯一依据；缺失时结论降级为「未取证」并**显式列出**，不静默补全。
本报告中**所有阻塞级结论均由本地证据支撑**，联网失败未影响定案。

---

## 四、建议下一步（需用户裁决）

1. **双面板目标确认**：本台够用 / 通用镜像？（决定 G01 路线 A 还是 B）
2. **v14 合成 + 刷写**（待办 #1）：v13 内核 + v10 切根 init，加 `deferred_probe_timeout=30`
3. **树内 grep `sdm660-internal`**：确认声卡驱动是否已在 7.0.14 树内（决定音频是自写还是移植）
4. **补 G02/G08**：panel@1 补 port/endpoint + Kconfig 补 GPIOLIB（低成本、高收益）
