# R11s v14 问题汇总表

> 生成：2026-09-02 · 基线：**v13 实刷镜像**（实机日志 `v13_dmesg_dedup.txt` 758 行）
> 方法：Wave 0 联网同 SoC 社区情报 → Wave 1/2/3 七域子代理并行取证 → Hub 汇总
> 证据约定：本地证据附 `文件:行号`；联网结论标 `[联网·佐证级]`；无证据项显式列「未取证」。
> 域明细：`recon/v14_domains/DOMAIN_*.md`；账本：`recon/orchestration/LEDGER_v14_20260902.md`

## 图例

- 类别：`功能缺陷` / `性能瓶颈` / `兼容性异常` / `用户痛点`
- 优先级：P0 = 阻塞 v14 目标 / P1 = 影响可用性 / P2 = 技术债与优化

---

## 一、触摸域（rmi4 / s3508 F12）

| ID | 现象 | 类别 | 证据（文件:行号） | 优先级 | 阻塞 |
|---|---|---|---|---|---|
| T1 | F12 Control 描述符读回全 0 → `size_presence_reg==0` → 发出**零长读**，被 i2c core `I2C_AQ_NO_ZERO_LEN` 在 `master_xfer` **之前**拒为 -95 | 功能缺陷 | `drivers/input/rmi4/rmi_driver.c:887`（len=0 的 `rmi_read_block`）；`:877`（`size_presence_reg < 0` 对 u8 恒假，死代码，漏判 `==0`）；实机日志 `:403-421` | P0 | 是 |
| T2 | f12 probe 失败后 `return -EPROBE_DEFER` **无重试上限** → 无限循环，永不停止 | 性能瓶颈 | `drivers/input/rmi4/rmi_f12.c:470 / 480 / 490`（三处 defer 出口，实机命中 480）；`:370`（attempt 上限 2）；`:386-402`（软复位 + 200ms settle） | P0 | 是 |
| T3 | 对确定性错误 `-EOPNOTSUPP` 仍重试 10 次 × 24ms，纯属浪费 | 性能瓶颈 | `drivers/input/rmi4/rmi_i2c.c:198-206`（retry 循环）；`:25-26`（`RMI_I2C_RETRY_TIMES 10` / `DELAY 20ms`）；`:207-210`（-95 被吞成 -EIO/-5） | P1 | 否 |
| T4 | 每轮软复位一次触摸传感器（约每 200ms 一次，持续折腾硬件） | 兼容性异常 | `rmi_f12.c:386-402`；日志 `:713`、`:742` `soft-resetting sensor before descriptor retry` | P1 | 否 |
| T5 | dmesg 持续刷屏（每轮约 50 行 printk，永不停止），救援 shell 被 echo 搅乱 | 用户痛点 | 日志 `:404-756`；HANDOFF §五 | P1 | 否 |

**量化（T2）**：每轮约 680ms，稳态周期 704–727ms → **占空比 82–96%，独占 `deferred_probe_work` 全局串行队列**；I2C 总线占用≈0（失败在 master_xfer 之前），CPU 约 10%（单核，msleep 外的 printk/调度）。

---

## 二、显示域（DPU / 时钟 / 面板）

| ID | 现象 | 类别 | 证据 | 优先级 | 阻塞 |
|---|---|---|---|---|---|
| D1 | `mdp_clk_src` RCG 未 latch 新配置 → `update_config()` 轮询 500×1µs 超时，WARN 并返回 -EBUSY | 功能缺陷 | `drivers/clk/qcom/clk-rcg2.c:114-138`（轮询 `CMD_UPDATE` 位，500 次后 WARN + `-EBUSY`）；日志 `:567-568` | P0 | 是 |
| D2 | `dpu_kms_init` **无条件** `dev_pm_opp_set_rate(dev, ULONG_MAX)` 且**返回值未检查** → -EBUSY 被静默吞掉 | 功能缺陷 | `drivers/gpu/drm/msm/disp/dpu1/dpu_kms.c:1309-1315`（`max_freq=ULONG_MAX`、`find_freq_floor`、set_rate 无条件且无返回值检查） | P0 | 是 |
| D3 | `pm_runtime_enable()` 在 `dev_pm_opp_set_rate()` **之后** → 换父时钟（MMPLL5）时 MDSS GDSC 很可能未上电 | 功能缺陷 | `dpu_kms.c:1315`（set_rate）vs `:1324`（pm_runtime_enable） | P0 | 是 |
| D4 | `&mdp` 节点缺 `operating-points-v2`，但调用栈证明 OPP 表确实存在 → 来源待查 | 功能缺陷 | `arch/arm64/boot/dts/qcom/sdm660.dtsi:204-207`（`&mdp` 无 opp 表） | P1 | 否 |
| D5 | `mdp_clk_src` 无 `CLK_SET_RATE_PARENT` / `CLK_OPS_PARENT_ENABLE`；最高频 412.5MHz 需父时钟 MMPLL5 | 功能缺陷 | `drivers/clk/qcom/mmcc-sdm660.c:952-976`（freq_tbl + init_data 无 flags）；`:2341-2346`（下游 branch 却带 `CLK_SET_RATE_PARENT`） | P1 | 否 |
| D6 | DPU 靠 component 聚合的 **deferred probe 兜回**才 bind 成功（首次 probe 未就绪） | 兼容性异常 | `drivers/gpu/drm/msm/msm_drv.c:1089`（`component_master_add_with_match`）；日志 `:615` `deferred_probe_work_func`；`sdm660.dtsi:296-305`（`&mmcc` 依赖 DSI PHY 时钟 → 探测顺序耦合） | P1 | 否 |
| D7 | 树内 `sdm660-oppo-r11s.dts`（212 行）grep `mdss|dsi|panel` **零命中**，显示链 100% 依赖手术 DTB | 用户痛点 | `.sdm660-oppo-r11s.dtb.dts.tmp:1630-1656 / 1732-1770 / 3045-3119`（mdss/dsi0/dsi1 全 disabled） | P1 | 否 |

**关键澄清**：D1 的 WARNING **发生在 deferred probe 重试路径内部**（日志 `:615`），因此加 `deferred_probe_timeout` 对 D1 **零收益**，仅对 D6 这类"bind 不起来"的场景兜底。

---

## 三、音频域

| ID | 现象 | 类别 | 证据 | 优先级 | 阻塞 |
|---|---|---|---|---|---|
| A1 | **R11s 专用 machine driver `CONFIG_SND_SOC_SDM660_OPPO_R11S` 未启用**：`.config` 显式 `is not set`、defconfig 中完全缺失，但源码 `sdm660-oppo-r11s.c` 存在 | 功能缺陷 | `build/r11s_phase2/.config:4469`；`sound/soc/qcom/Kconfig:182`；`sound/soc/qcom/sdm660-oppo-r11s.c` 存在 | P0 | 是 |
| A2 | 声卡 `sdm660-int-sndcard` defer（内核侧依赖未就绪，非 DTB 属性缺失——v12 DTB 音频节点齐全） | 功能缺陷 | `sound/soc/qcom/sdm660-internal.c:460-470`（compatible `qcom,sdm660-internal-sndcard`）；DTB `dtb_v12.verify.dts:3254-3339`（model/audio-routing/dai-link 齐全） | P0 | 是 |
| A3 | `152c000.audio-codec` defer = LPASS 内建 WCD 数字 codec，其 clocks 依赖 `&q6afecc`（ADSP APR） | 功能缺陷 | `.sdm660-oppo-r11s.dtb.dts.tmp:2431-2445`（`lpass_codec`，树内默认 `status="disabled"`）；`:2495` `q6afecc`；DTB `:2899-2909`（实刷 DTB 中为 okay） | P1 | 否 |
| A4 | `internal MI2S` 在 `sound/soc/qcom/**/*.c` 中 **grep 零命中**，是否具备端口定义未证实 | 未取证 | grep `internal.?mi2s|int_mi2s|INTERNAL_MI2S` → 0 命中；头文件 `qcom,q6dsp-lpass-ports.h` 确有被 `sdm630.dtsi` 引用 | P2 | 否 |
| A5 | codec compatible 未跟随上游（用下游别名 `qcom,pmic-analog-codec` / `qcom,msm-digital-codec`，非 PM660L / SDM660） | 兼容性异常 | `sound/soc/codecs/msm8916-wcd-analog.c:1417`；`msm8916-wcd-digital.c:1239` | P2 | 否（**建议不改**，见方案） |

**已补齐的 Wave 1 缺口**：`CONFIG_SND_SOC_SDM660_INT` 两处均 `=y`（`r11s_defconfig:526` / `.config:4468`）——基础音频通路已开，A1 是独立缺口。

---

## 四、WiFi / 蓝牙 / 外设固件域

| ID | 现象 | 类别 | 证据 | 优先级 | 阻塞 |
|---|---|---|---|---|---|
| W1 | **驱动请求的 `ath10k/WCN3990/hw1.0/firmware-5.bin` 不存在**；清单该目录只有 `board-2.bin` + `wlanmdsp.mdt/b03/b04/b06/b07` | 功能缺陷 | `drivers/net/wireless/ath/ath10k/hw.h:125,138` + `core.c:1325`（请求串）；清单 `firmware/ath10k/WCN3990/hw1.0/` 实列 | P0 | 是 |
| W2 | 原厂 `wlanmdsp.mbn`（3.32MB）被孤立在 `firmware/archive/`，**未安装到驱动请求路径** | 功能缺陷 | 清单 `firmware/archive/wlanmdsp.mbn`；`firmware/archive/bdwlan_variants/`（下游 wcnss 用，主线 ath10k 不用） | P0 | 是 |
| W3 | `wlanmdsp.mbn` 版本可能不兼容 mainline ath10k（**风险未证实**） | 兼容性异常 | `[联网·佐证级]` jason 移植报告：原厂 1.0.0.533 / htt-ver 3.50 → WiFi 起后约 350ms fatal error（PC=b00c749c）；需换 whyred V12 的 NON-HLOS.bin（1.0.0.591 / htt-ver 3.58） | P0 | 是（上板前必须裁决） |
| W4 | BT `qca/crbtfw21.tlv` 加载 -2 = **救援 ramdisk 未打包**（路径字符串与内核请求逐字一致，非路径错误） | 功能缺陷 | 清单 `firmware/qca/crbtfw21.tlv`（113,976 B）存在；日志 `:521-523` 请求串完全相同 | P1 | 否 |
| W5 | `qcom/sdm660/adsp.mdt`、`cdsp.mdt` 在救援 ramdisk 加载 -2（rootfs v3 内有，切根后可补） | 功能缺陷 | 清单 `firmware/qcom/sdm660/adsp.mdt`(7,964 B)、`cdsp.mdt`(7,068 B) 存在；日志 `:553-561` | P1 | 否 |
| W6 | WiFi 依赖 modem DSP；v13 日志未见 mss 报错，但是否真正起来**未证实** | 未取证 | DTB `dtb_v12.verify.dts:1470-1496`（`remoteproc@4080000` status=okay, firmware-name `mba.mbn\0modem.mdt`，与清单无前缀布局匹配）；`[联网·佐证级]` 社区：WiFi 必须启用 modem | P1 | 否 |

**WiFi 供电结论**：`wifi@18800000` 四路供电齐全且 status=okay（`dtb_v12.verify.dts:3140-3156`），与社区参考一致，**不存在缺供电问题**——缺口纯在固件。

**DTB 命名陷阱**：modem 用无前缀 `mba.mbn\0modem.mdt`（`:1487`），adsp/cdsp 用带前缀 `qcom/sdm660/adsp.mdt`（`:2924`），二者与清单实际布局**均一致**。**不要**照抄社区教程给 modem 补前缀，否则引入新的 ENOENT。

---

## 五、GPU 域（Adreno 512）

| ID | 现象 | 类别 | 证据 | 优先级 | 阻塞 |
|---|---|---|---|---|---|
| G1 | `gpu@5000000` 节点**完全没有 `*-supply` 属性** → dummy regulator（属"DTB 没写"，非"名字写错"） | 功能缺陷 | `dtb_v12.verify.dts:1498-1514`（节点全属性，无 supply）；`drivers/gpu/drm/msm/msm_gpu.c:1051,1056`（硬编码请求 `"vdd"` / `"vddcx"`） | P0 | 是 |
| G2 | `a530_pm4.fw` + `a530_pfp.fw` 缺失（a5xx 全家族共用此微码名，非驱动选错） | 功能缺陷 | `drivers/gpu/drm/msm/adreno/a5xx_catalog.c:110-125`（512 条目请求 a530_pm4/pfp + `a512_zap.mdt`）；日志 `:623-624`；清单 `*a5*` 递归搜索 0 命中 | P0 | 是 |
| G3 | `a512_zap.mbn` 缺失，但 DTB zap-shader 节点引用它 → **双重缺口** | 功能缺陷 | `dtb_v12.verify.dts:1570-1573`（`firmware-name = "a512_zap.mbn"`）；`adreno_gpu.c:75-78`（direct 路径取该名） | P0 | 是 |
| G4 | GPU 真实水平 = **绑定成功但 3D/渲染未初始化**；"显示能亮"来自 DPU，不等于 GPU 可用 | 功能缺陷 | `adreno_device.c:86-99`（load_fw 失败 → `return NULL`，3D 初始化终止）；`adreno_gpu.c:603-626` | P1 | 否 |
| G5 | 无调压状态下顶频运行（DTB 最高 OPP 588MHz） | 兼容性异常 | `dtb_v12.verify.dts:1516-1568`（opp-table，最高 `opp-588000000`）；`msm_gpu.c:26-55`（只有 enable/disable，**全树 msm 目录无 GPU 调压调用**） | P2 | 否 |

**对"dummy regulator"的澄清**：upstream 从不给 GPU 调压（电压由 OPP/opp-level + GDSC perf state 承担），因此 dummy **不会**造成频率失控/过热；真实影响是「无法断电轨省电」+「顶频长期运行欠压不稳风险」。需实测定性。

**`ops a3xx_ops` 不是 bug**：`find_chipid()` 从 `qcom,adreno-512.0` 解析出 `0x05010200` 命中 `a5xx_catalog.c:110` 的 512 条目。不要为此改驱动。

---

## 六、构建 / 打包 / 验证域

| ID | 现象 | 类别 | 证据 | 优先级 | 阻塞 |
|---|---|---|---|---|---|
| B1 | 15 个本地提交中 **7 个标注「验证状态=未上板」**，多数修复从未实机验证 | 用户痛点 | `git log --oneline -12`：`ddff10388`、`d947f542d`、`476821c28`、`a02aced7f`、`b55601e7d`、`e520efd19`、`ce07c13f5`、`11bf7be6f` | P0 | 是 |
| B2 | `r11s_bootimg_pack.py` 的 CANON 默认值与 v13 既有事实冲突（base 0x0 vs 0x80000000 等）→ v14 必须逐项显式传参 | 用户痛点 | `tools/r11s_bootimg_pack.py:22-37`（dry-run 默认、`--write` 落盘）；脚本默认值 vs v13 实际 header | P1 | 否 |
| B3 | v10 切根镜像基于 **v9 内核**，不含 v12 评审修复与 v13 诊断 → 直接刷会丢显示链修复 | 功能缺陷 | `out/boot_r11s_phase4_rootfs_v10.img`（15,081,472 B，sha256 `28773a5c…`）；v10_release_body.md:8 | P1 | 否 |
| B4 | v13 的 ramdisk 与 v10 归档的 `ramdisk_v9_orig.cpio` **哈希完全相同**（`1ad74196…`）→ 印证 v13 无切根 init | 功能缺陷 | 交叉核对（Wave 2 构建域） | P1 | 否 |

---

## 七、文档域

| ID | 现象 | 类别 | 证据 | 优先级 | 阻塞 |
|---|---|---|---|---|---|
| DOC1 | HANDOFF ↔ STATUS **6 处不一致**（defer 定性强度、PDT 修复记载、回滚链成员、设备当前态、WiFi 就绪度、新产物登记） | 用户痛点 | `HANDOFF.md:41`（"定性为时序竞态"）vs `STATUS.md:356`（"强烈指向"）；`STATUS.md:286,349` 回滚链漏 v10；`STATUS.md` 6 处"设备当前态"其中 5 处已失效且无过期标注 | P1 | 否 |
| DOC2 | 「冲突时以 STATUS.md 为准」只存在于 `HANDOFF.md:5`，STATUS.md 全文 0 命中 → 仲裁规则是**单向声明**，且 STATUS 是 append-only 流水账 | 用户痛点 | grep `快照|冲突|为准` → STATUS 0 命中 | P1 | 否 |
| DOC3 | v13 归档 README 称 `devices_deferred` 为空，与实机 `-5 deferring probe` 矛盾（cat 恰好抓到瞬态空档） | 用户痛点 | `products_r11s_phase3_regdiag_v13_flash_20260901_2200/README.md:34-36` vs 日志 `:698/727/756` | P1 | 否 |
| DOC4 | `CLAUDE.md §0` 仍写"尚未建立内核树/rootfs/测试镜像"，与实际进度（已刷到 v13、有 rootfs v3）严重脱节 | 用户痛点 | `CLAUDE.md:8-14` | P2 | 否 |
| DOC5 | 本轮三个新产物（`AGENT_ORCHESTRATION.md`、双面板差距清单、账本）**尚未登记**进 HANDOFF/STATUS | 用户痛点 | — | P1 | 否 |
| DOC6 | `PLAN.md` 的 P0/P1/P3 checkbox 全空但实际已完成，且缺 P5 阶段 | 用户痛点 | `PLAN.md:9-47` | P2 | 否 |

---

## 八、联网映射结果（同 SoC 社区 → 本项目）

| 社区结论 `[联网·佐证级]` | 来源 | 可平移性 | 映射到本项目 |
|---|---|---|---|
| SDM660 主线：WiFi(WCN3990+ath10k_snoc) ✅ / BT ✅ / Display ✅ / Storage ✅ | jason 移植报告 §3 | **可平移**（驱动能力存在） | 印证 W1/W2 缺口在固件打包，非主线能力 |
| 原厂 `wlanmdsp.mbn` 1.0.0.533 / htt-ver 3.50 → WiFi 起后 ~350ms fatal error | jason §12.1 | **高价值预警** | → W3，上板前必须 `strings` 核对版本 |
| wlanmdsp 与 modem 组件**强耦合**，单换会 modem watchdog timeout | jason §12.1-4 | **可平移** | → W3 必须整组替换，不可只换 wlanmdsp |
| WiFi **依赖 modem DSP**，不能禁用 modem | jason §12.2 | **可平移** | → W6，v14 必须抓 mss 加载行 |
| QMI 协商需**冷启动**，warm reboot 会致状态不一致 | jason §12.1-6 | **可平移** | → v14 测试流程约束 |
| GPU(Adreno 512) ⚠️ Partial：KMS/fbcon OK，3D 不完整 | jason §3 | **可平移** | → G4，与本项目 G2/G3 固件缺口吻合 |
| Audio ⚠️ Partial | jason §3 | 部分可平移 | → A2/A4 |
| ABL 必须验证 `qcom,msm-id/board-id/pmic-id`，缺则拒绝启动 | jason §12.1-1 | **已满足**（本 DTB 有） | 无动作，留作风险备忘 |
| 多面板变体用**一变体一 DTB + kernel 子包**（lavender 三个面板子包） | pmaports device-xiaomi-lavender | **可平移** | 印证双面板差距清单 G01 路线 A |
| SDM660 声卡上游补丁 v1(2026-02,10 补丁) → v4(2026-05,15 补丁)，**合入状态未证实** | `lwn.net/Articles/1058301`、`ratatoskr.run/.../8251534` | **部分可平移** | 树内已有本地移植版 `sdm660-internal.c`（12.28KB，非上游 271 行原始版），**"移植"与"上游合入"须区分表述** |

**联网失败项（显式列出，均已降级为「未取证」）**：
- `postmarketOS` SDM660 wiki —— Anubis 反爬拦截（返回 "Making sure you're not a bot!"）
- `github.com/sdm660-mainline` 组织页 —— 请求超时 10s
- `oppo-source/FindX-8.1-kernel-source` 的 sofeg01 dtsi —— GitHub raw 超时
- `sofeg01` / `ams596w401` 公开型号资料 —— 全网零结果（与上一轮结论一致）
- `node` 不可用 → Web Access skill 的 CDP 浏览器路径整体不可用，本期全程用 `web_search` / `web_fetch`
