# R11s 项目交接文档（给新 agent）

> 生成时间：2026-09-01 深夜。交接人：上一轮会话 agent。
> 项目根：`/home/<user>/claude/r11`。必读：`CLAUDE.md`（硬规则）、`STATUS.md`（完整历史）、`PLAN.md`。
> **本文件是快照，冲突时以 STATUS.md 最新条目为准。**

---

## 一、已完成（全部有归档和 hash 可复核）

### 基础设施与取证（P0–P1，2026-07~08）

- 官方 C.19 OZIP 解密、boot.img 提取、9 DTB 取证（board-id 0x4273=17011，面板 SOFEG01_S 定案）。
- `fastboot boot` 实测不支持（ABL 只认 flash boot）→ 开发路径 = 反复 flash boot 分区。
- ABL 镜像大小门禁已验证：解压后 Image ≥ 0x3180000 (49.5MiB) 被拒（记忆 r11s-mainline-abl-image-size-gate）。
- 主线 7.2 内核被 ABL 拒的 6 组组合实验已收敛（详见 STATUS.md 2026-08-01 节）→ 转向第三方适配树。

### 当前活跃内核线（阶段 2 起）

- 树：`out/linux-sdm660-oppor11-t-qcom-sdm660-7.0.y`（Linux 7.0.14，分支 main，已推 GitHub）。
- 构建目录：`build/r11s_phase2`，vermagic `7.0.14-sdm660-gcc++`。
- 打包工具：`tools/r11s_bootimg_pack.py`（dry-run → --write，参数见各 README）。

### 实机成果时间线（设备 = Oppo R11s，serial 9144dacf）

| 版本 | 内容 | 实机结果 |
|---|---|---|
| stage1/dtbsurg | 下游 4.19 内核+手术 DTB | PASS（首次证明 ABL 面板参数） |
| phase2 v2 | 本地重编 7.0.14 | PASS（救援 shell 2min+） |
| v6 | 触摸+显示（sofeg01_s） | **显示打通（用户亲见企鹅）** |
| v8 | 触摸 PDT 修复 | 触摸中断链路 OK，坐标不出（F12 描述符读不出） |
| v9 | 四路集成（触摸/音频/WiFi/电池 config） | 刷过（用户日志） |
| v12 | 评审修复 + defconfig 回写 + panel@1 disabled | 面板 regulator defer（11.75s） |
| **v13** | v12 + 面板驱动逐条供电 errno 诊断（提交 419244cc3） | **PASS：面板完全成功，defer 未复现** |

### v13 实机结果（2026-09-01 晚，最新定案）

- 救援 gadget t+3s 出现（历史最快），shell 可用（ttyACM0）。
- 显示链完整打通：OLEDB 3.40s 使能 → sofeg01_s 3.75s probe 成功（power mode 0x9e）→ fbcon/fb0 3.86–3.95s。
- `devices_deferred` 为空；面板三条供电（oledb/vdd/vddio）regulator_summary 全绑定。
- **v12 的 defer 定性为时序竞态**（v12→v13 唯一差异 = +3347B 诊断代码，时序挪动即翻正）。
- 归档：`backups/products/products_r11s_phase3_regdiag_v13_flash_20260901_2200/`。

### 主机侧成品（未刷，待用）

- **rootfs v3**：`out/r11s_phase4a_rootfs_v3.ext4`（192MiB，sha256 f54772b7…）= Alpine minirootfs + 681 模块 + 110 固件文件 + WiFi userspace 四件套（rmtfs/pd-mapper/qrtr-*）。v2/v1 为回滚件。
- **v10 切根镜像**：`out/boot_r11s_phase4_rootfs_v10.img`（15,081,472 B，sha256 28773a5c…）= v9 内核+DTB + 新 /init（root=/dev/mmcblk1p69 挂载切根，失败落回救援 shell）。
  - **注意**：v10 基于 v9 内核（不含 v12 评审修复/v13 诊断）。若要显示链完整，建议先做 v14 = v13 内核 + v10 的切根 init。
- rootfs 写入脚本：`tools/r11s_phase4_emmc_setup.sh`（默认干跑，需用户双重确认）。

### 源码提交（仓库 main，已推送）

- b7015cc53：评审修复（smbx 限流 4.8A 上限、rmi4 双重释放、f12 软复位查返回值）
- 08456b1e7：r11s_defconfig 回写（966 行最小集）
- 419244cc3：v13 面板驱动逐条供电诊断

---

## 二、未完成（已知问题清单）

### 按优先级

1. **阶段 4（rootfs 切根）整体未执行** — 主机侧材料齐备，等用户授权：
   - 缺一个"v14"：v13 内核 + v10 切根 init 的合成镜像（v10 现在基于 v9，不含 v12/v13 增量，直接刷会丢显示链修复）。
   - p69（userdata ~46.3GiB）未格式化、rootfs 未写入。
2. **触摸不出坐标**：s3508 F12 Control Register Descriptor 读不出（I2C -95，addr 0x20，零长读 quirk 报错）。v8 已排除中断/供电/链路问题，就卡在 F12 描述符。周期性 retry+defer，不超时。
3. **固件缺失（救援 ramdisk 内）**：切根后由 rootfs /lib/firmware 补：
   - `qcom/a530_pm4.fw`（GPU 加速，fbcon 不受影响）
   - `qcom/sdm660/adsp.mdt`、`cdsp.mdt`（remoteproc -2）
   - `qca/crbtfw21.tlv`（BT 固件名可能与 rootfs 内文件名不一致，需核对）
4. **音频**：声卡 `sdm660-int-sndcard` defer（MultiMedia1 cpu dai 名错误）+ `152c000.audio-codec` defer——预期内（DTB 下游绑定，`SND_SOC_SDM660_OPPO_R11S` 未启用，需要写机器驱动，未开始）。
5. **DPU warning**：`mdp_clk_src: rcg didn't update its configuration`（clk-rcg2.c:136）不阻塞 fbcon，未查。
6. **WiFi**：ath10k snoc config 已开，实机未验证（大概率卡在 firmware + wcn3990 供电序列，未开始）。
7. **v12 竞态复验**（科学性，非必需）：复刷 v12 看 defer 是否复现。已建议跳过，用 v14 加 `deferred_probe_timeout=30` 兜底。

### cmdline 取证（新发现，未深挖）

ABL 注入参数被树内过滤补丁吃首字符：`_oot=`、`_nit=`、`_kip_initramfs`（防 root=/init= 劫持），但 `mdss_mdp.panel=...` 原样保留 → 过滤是选择性黑名单。实现细节未查（在树里找 `cmdline` 过滤补丁即可）。

---

## 三、下一步计划（建议顺序）

### 第 1 步：v14 合成镜像（纯主机侧，立即可做）

- 内容 = v13 的 Image.gz/dtb_v12.dtb（逐字节复用）+ v10 的 ramdisk（切根 /init，root=/dev/mmcblk1p69）。
- 打包用 `tools/r11s_bootimg_pack.py`，参数同 v10 但 kernel 换 v13 的。
- cmdline 建议加 `deferred_probe_timeout=30`（竞态兜底）。
- 门禁：解压 Image ≤ 0x3000000；dry-run 哈希对账。
- 归档到 `backups/products/products_r11s_phase4_v14_<时间戳>/`。

### 第 2 步：刷 v14（需用户当次确认）

- 先不格式化 p69：预期行为 = 切根失败落回救援 shell（防砖验证 /init 逻辑）。
- 刷前确认回滚链：v14→v13→v12→…→boot-debug.img（4ff811c3…）。

### 第 3 步：写 rootfs（需用户当次确认，脚本双重确认）

- `tools/r11s_phase4_emmc_setup.sh`：救援 shell 拉 configfs mass_storage LUN → 主机 dd `out/r11s_phase4a_rootfs_v3.ext4` 到 p69。
- 完成后再刷 v14 → 预期挂载 p69 切根成功 → Alpine shell + rmtfs/pd-mapper 自拉起。

### 第 4 步：切根后验收清单

```
/proc/version（7.0.14-sdm660-gcc++）
ls /lib/modules/7.0.14-sdm660-gcc++（681 模块）
ls /lib/firmware/qcom/sdm660/（adsp/cdsp）
dmesg | grep -iE "adsp|cdsp|rproc"（固件加载成功与否）
ip a（rmtfs 起来后 modem 状态）
hcidump / dmesg | grep -i bluetooth（crbtfw21 加载）
```

### 第 5 步（阶段 5 方向，未规划细节）

触摸 F12 深挖 / 音频机器驱动 / WiFi 上板。可按用户兴趣排序。

---

## 四、新 agent 必须遵守的规则（摘要，全文见 CLAUDE.md）

1. **触设备动作**（刷写/格式化/写分区/进 recovery）必须先展示命令+目标分区+回滚路径+风险，取得**用户当次明确确认**。历史惯例：用户说"刷"才算授权。
2. 备份优先：改源/改 DTS/出镜像前先备份 `backups/source/`，产物归档 `backups/products/`，带 hash+README。
3. 禁止 MTK/R11/R11s Plus 混淆；禁止 9008 自定义刷写（仅原厂救援）。
4. 设备调试走 USB gadget（ttyACM0）；早期崩溃考虑 pstore/ramoops。
5. Linux 4.19 树（linux-4.19.325/）与本 Ubuntu 线隔离，不互相影响。
6. **说话正常**：用户明确要求不要一句几个回车/碎片化输出。
7. 派 agent 干活用 Sonnet，别用 Haiku；任务细粒度。

## 五、设备当前状态（交接时刻）

- **运行 v13 救援 shell**（不是 fastboot）。USB gadget = ttyACM0（18d1:d004）。
- boot 分区里是 v13。回滚终极件：`boot-debug.img`（4ff811c3…，4.19 Lineage）。
- 救援 shell 注意事项：busybox ash；内核 rmi4 触摸驱动会周期性刷屏（dmesg -n 1 可静默）；shell 输入易被 echo 搅乱，命令前带 `\n`，常备 Ctrl+C 清理；传文件用 base64 分块或 dd 分块+去重。

---

# 2026-09-02：v14 规划轮（Wave 0-4 编排，主机侧，未触碰设备）

> 本轮按 `AGENT_ORCHESTRATION.md`（Hub-and-Spoke + Wave 调度）执行：Wave 0 联网同 SoC 社区情报 → Wave 1/2/3 七域子代理并行取证 → Wave 4 Hub 汇总。**全程只读取证，未改源码、未打镜像、未刷机。**

## 一、本轮交付物

| 文件 | 内容 |
|---|---|
| `recon/R11S_V14_ISSUE_MATRIX_20260902.md` | 问题汇总表（七域 30 项，含类别/证据/严重度/阻塞性）+ 联网映射结果 |
| `recon/R11S_V14_IMPROVEMENT_PLAN_20260902.md` | v14 改进方案，分 v14a 止血 / v14b 根治 / v15 深水区，改动精确到 `文件:行号` |
| `recon/R11S_V14_IMAGE_PLAYBOOK_20260902.md` | v14 镜像合成步骤 + 6 项门禁 + 7 级回滚链 + 待授权命令（**未执行**） |
| `recon/v14_domains/DOMAIN_{touch,display,audio,wireless,gpu,build,docs}.md` | 七域证据档案 |
| `recon/orchestration/LEDGER_v14_20260902.md` | 本轮账本（新增「置信度」「反驳证据」列） |

## 二、根因级发现（此前未定案）

1. **触摸**：`-95` 不是适配器不支持块读，而是 `rmi_driver.c:887` 在 `size_presence_reg==0` 时发出**零长读**，被 `I2C_AQ_NO_ZERO_LEN` 在 `master_xfer` 之前拒绝；`:877` 的 `< 0` 是 u8 恒假死代码。`rmi_f12.c:470/480/490` 三处 `return -EPROBE_DEFER` **无重试上限** → 无限循环，每 704–727ms 一轮，**独占 `deferred_probe_work`（占空比 82–96%）**。
2. **显示**：`dpu_kms.c:1309-1315` **无条件** `dev_pm_opp_set_rate(dev, ULONG_MAX)` 且**返回值未检查**；且发生在 `pm_runtime_enable()`（:1324）**之前** → 换父时钟（MMPLL5）时 GDSC 未上电 → `clk-rcg2.c:114-138` 轮询 500×1µs 超时返回 -EBUSY。**这不是无害 warning，MDP 频率实际未生效。**
3. **音频**：`CONFIG_SND_SOC_SDM660_OPPO_R11S` 在 `.config:4469` 显式 `is not set`、defconfig 完全缺失，而源码 `sdm660-oppo-r11s.c` 存在 → R11s 专用 machine driver 根本没编译。（`SND_SOC_SDM660_INT` 两处均 =y。）
4. **WiFi**：驱动请求 `ath10k/WCN3990/hw1.0/firmware-5.bin`，清单中**不存在**；原厂 `wlanmdsp.mbn` 孤立在 `firmware/archive/` 未安装。
5. **GPU**：`gpu@5000000` 节点**完全无 `*-supply` 属性**（驱动硬编码请求 `vdd`/`vddcx`，`msm_gpu.c:1051/1056`）；`a530_pm4.fw` / `a530_pfp.fw` / `a512_zap.mbn` **三项全缺**（后者被 DTB:1572 引用）。
6. **谱系实证**：v13 的 `ramdisk_v6.cpio` 与 v10 归档的 `ramdisk_v9_orig.cpio` **哈希相同**（`1ad74196…`）→ **v13 确实不含切根 init**（哈希实证，非推断）。

## 三、对既有文档记载的修正

- **`devices_deferred` 为空 ≠ 没有 defer**：该设备几乎总处于"正在 probe"或"刚入队"瞬态，`cat` 恰好抓到空档。实机持续 `-5 deferring probe`。
- **v12 defer 定性**：`STATUS.md` 的「强烈指向时序竞态」是本轮采纳的措辞；旧条目中「定性为」把未证实假设升级成了定案。但本轮已找到**可修的具体代码点**（D1-D3），因此**不建议**再花时间复刷 v12 验证竞态。
- **回滚链补 v10**：`STATUS.md:286 / :349` 的链条均漏了 v10，而 v10 是唯一切根镜像。已在合成预案中补全 7 级链。
- **v8 的 PDT 修复**（PDT_END 0x05→0xd0、10 页扫描上限、幽灵函数白名单、原厂布局回退）仅记载于 `STATUS.md:200-202`，HANDOFF 缺失，交接时易丢失。

## 四、下一步（需用户裁决）

1. **v14a 是否全纳入**（9 项低风险改动，见改进方案 §二）；
2. **v14b 的 GPU 供电（B-4）是否单独出包**——这是本轮最高风险项；
3. **A-6 固件版本核对**必须在 v14 上板前完成（决定 WiFi 是否要走整组替换）；
4. 刷写 v14、格式化 p69、写 rootfs —— **均需用户当次明确确认**，预案已备好命令与回滚链。

---

# 2026-09-02 增补：v14a/v14b 已实刷实测（本节取代上方"下一步"中已完成的 1/3/4 项）

## 当前设备状态（唯一有效）

- **在机镜像：v14b**（`5d1e2c8b42f7…`，内核 #14 = `f901d1b99`+`8f1116321`），运行救援 shell（USB `18d1:d004`，`/dev/ttyACM0` 经 `tools/acm_cmd.sh` 交互）。
- p69（23.2GB）未格式化；rootfs v3 未写入。
- 回滚链：v14b→v14a→v13→v12→v11→v10→v9→…→boot-debug.img（`4ff811c3…`）。

## 已定案（全部实机验证，证据 `recon/v14{a,b}_dmesg_full_20260902.log`）

| 改动 | 提交 | 实测结果 |
|---|---|---|
| A-1 零长读快速失败 + A-2 F12 defer 封顶（含清 IRQ 位） + A-3 传输层确定性错误不重试 | `f901d1b99` | 无限 defer 循环根治；v14b 轮次触摸 **`Synaptics s3508` 注册为 event0** |
| A-4 `CONFIG_SND_SOC_SDM660_OPPO_R11S=y` | `f901d1b99` | 驱动已内建；声卡仍 defer（ADSP 链，v15） |
| A-8 ramdisk 补 `qca/crbtfw21.tlv`+`crnv21.bin` | 打包侧 | **蓝牙首次完全初始化**（`QCA setup on UART is completed`） |
| B-1 dpu set_rate 前置 rpm_get_sync + B-2 mdp_clk_src `CLK_OPS_PARENT_ENABLE` | `8f1116321` | `mdp_clk_src` 警告消失；暴露下一环 `pclk0_clk_src`（v15） |
| B-5 a530_pm4/pfp 微码入 ramdisk+固件清单 | 打包侧 | 加载成功；GPU 3D 卡在 `a512_zap.mbn` 缺失（v15） |
| B-4 GPU 供电 / B-3 OPP 表 / A-7 整组替换 | — | **未做**（按方案风险定级） |

## 立即下一步（按优先级）

1. **切根实测**：格式化 p69 + 写 rootfs v3（`tools/r11s_phase4_emmc_setup.sh`，脚本内置双重确认，**需用户当次授权**）→ 验证 `root=/dev/mmcblk1p69` 切根链。
2. **v15 清单**（详见 `recon/R11S_V15_PREP_20260902.md`）：pclk0_clk_src 修复、`a512_zap.mbn` 来源、音频 ADSP 链（cpu dai name）、ath10k `vdd-3.3-ch1` 供电、reboot-reason→fastboot 链路、A-6 固件版本核对（仍未取证）。
3. 触摸体验实测需人工在屏上滑动（救援 shell 下可 `cat /dev/input/event0 | xxd` 观察）。

---

## 2026-09-02 第三更：v15 已合成（未刷，设备仍在 v14b）

- **镜像**：`out/v15/boot_r11s_v15.img`（`f944aaf7…`，37,220,352 B），归档 `backups/products/products_r11s_v15_20260902_1244/`。
- **新增改动**（v14b 之上）：pclk0/pclk1 `CLK_OPS_PARENT_ENABLE`（V1）；**双面板自动检测 = ABL cmdline `mdss_mdp.panel=` 门控 + dsi_bind 同名选桥**（C-4 可行半边；本机可验证 sofeg01 选中 / ams596 被门控，另一变体命中仍需第二台机器）；DTB 补 `vdd-3.3-ch1-supply`（V4）；ramdisk 入 adsp/cdsp/ath10k 固件（音频首次可测）。
- **未做且不要凭猜测做**：`a512_zap.mbn` 无合法来源 → GPU 3D 仍停在 zap；modem（56MB，超 boot 预算）未入 ramdisk → WiFi 救援期仍大概率失败。
- **明早测试**：`recon/R11S_V15_MORNING_TEST_20260902.md`（每项含预期 dmesg 关键字）。刷写需当次授权：
  `fastboot flash boot out/v15/boot_r11s_v15.img && fastboot reboot`
  回滚：v14b → v14a → v13 → … → boot-debug.img。
