# DOMAIN_docs — 文档域

> Wave 3 · 子代理只读取证 · 2026-09-02

## 结论

1. **「冲突时以 STATUS.md 为准」这条仲裁规则只存在于 `HANDOFF.md:5`，STATUS.md 全文 0 命中**——规则是单向声明（HANDOFF 自认让位），STATUS.md 从未声明自己权威，且它是 append-only 流水账（含 5 处已过期的「设备当前状态」），在此结构下「以 STATUS 最新条目为准」可执行性存疑。
2. **HANDOFF 与 STATUS 的核心事实共 6 处不一致**，其中风险最高的是：`HANDOFF:41` 用「定性为时序竞态」而 `STATUS:356` 只说「强烈指向」——HANDOFF 把未证实的假设升级成了定案。
3. **本轮 8 条取证事实中，文档「已过时」2 条、「文档错误」2 条、「文档未覆盖」4 条、「文档正确」0 条**；唯一「正确」的部分仅是 v13 显示链打通这一结果本身，其支撑证据（`devices_deferred` 为空）已被推翻。
4. **`CLAUDE.md` 需重写 §0/§4/§5/§6（4 节），`PLAN.md` 需整体重排**（P0/P1/P3 已事实上完成但 checkbox 全空，且缺 P5 阶段）；`CLAUDE.md §1`（取证优先级）与 §3（备份归档）可原样保留。
5. **账本需在 `AGENT_ORCHESTRATION.md §11` 的 5 表模板上新增 7 个字段/小节**，核心是新增「置信度」与「反驳证据」列，否则无法承载「文档记载 vs 实机取证」的冲突登记。

## 证据

**仲裁规则的实际位置（推翻题目前提）**
```
HANDOFF.md:5   > **本文件是快照，冲突时以 STATUS.md 最新条目为准。**
search_content("快照|冲突时|为准", STATUS.md)  → Found 0 matching results
search_content("快照|冲突时|为准", HANDOFF.md) → 1 match (HANDOFF.md:5)
```

**#1 面板 defer 定性强度不同（风险最高）**
```
HANDOFF.md:41  - **v12 的 defer 定性为时序竞态**（v12→v13 唯一差异 = +3347B 诊断代码，时序挪动即翻正）。
STATUS.md:356  - **结论修正**：...强烈指向**时序竞态**（嫌疑 A 佐证），而非确定性缺陷。
STATUS.md:310  **当前最强嫌疑 = 时序回归**
STATUS.md:361  - 后续建议（待用户决定）：复刷 v12 验证竞态假设
HANDOFF.md:74  7. **v12 竞态复验**（科学性，非必需）：...已建议跳过
```
→ 两处分歧：(a)「定性为」vs「强烈指向/最强嫌疑」；(b)「已建议跳过」vs「待用户决定」

**#2 触摸 PDT 修复的记载层次不同**
```
STATUS.md:200-202  v8 上板实证... Nick 对照原厂修复：PDT_END 0x05→0xd0、
                   10 页扫描上限、幽灵函数白名单、原厂布局回退。
HANDOFF.md:31      | v8 | 触摸 PDT 修复 | 触摸中断链路 OK，坐标不出（F12 描述符读不出） |
HANDOFF.md:66      2. **触摸不出坐标**：...就卡在 F12 描述符。周期性 retry+defer，不超时。
```
→ STATUS 记载了 4 项具体 PDT 修复动作；HANDOFF 完全没有，且描述为「未奏效」。
→ **风险**：交接新 agent 会丢失 PDT_END / 10 页上限 / 幽灵白名单三条已做工作。

**#3 回滚链成员不一致（各期链互相不含，且 8-31 链漏 v10）**
```
STATUS.md:236  回滚链不变：v10→v9→v8→…→boot-debug.img
STATUS.md:256  回滚链不变：v10→v9→v8→…→boot-debug.img
STATUS.md:286  回滚链更新：v12→v11→v9→v8→…→boot-debug.img   ← 漏 v10
STATUS.md:349  回滚链更新：v13→v12→v11→v9→…→boot-debug.img  ← 漏 v10
HANDOFF.md:95  刷前确认回滚链：v14→v13→v12→…→boot-debug.img
HANDOFF.md:47  v10 切根镜像：out/boot_r11s_phase4_rootfs_v10.img（28773a5c…）
```
→ v10 是唯一的切根镜像，却在两条链中被跳过；HANDOFF:95 用「…」省略，无法与任一链对齐。

**#4 设备当前态：append-only 导致多份「当前态」并存**
```
STATUS.md:218  停在 fastboot（18d1:d00d）
STATUS.md:237  停在 fastboot（18d1:d00d）
STATUS.md:257  停在 fastboot（18d1:d00d）
STATUS.md:287  停在 fastboot（18d1:d00d）
STATUS.md:350  停在 fastboot（18d1:d00d）
STATUS.md:360  **运行 v13 救援 shell**（非 fastboot）   ← 唯一正确
HANDOFF.md:131 **运行 v13 救援 shell**（不是 fastboot）
```
→ STATUS 有 6 处「设备当前态」，其中 5 处已失效且**无「已过期」标注**。

**#5 WiFi 固件状态记载不同**
```
HANDOFF.md:73  6. **WiFi**：ath10k snoc config 已开，实机未验证（大概率卡在 firmware...）
recon/R11S_STATUS_DUALPANEL_GAP_20260901.md:35  | WiFi / BT | ❌ 未验证 | 固件在 rootfs 就位但未上板 |
```
→ 二者对同一事实给出不同就绪度。本轮已定案：**固件路径存在硬不匹配**（`firmware-5.bin` 缺失），两份文档都不准确。

**#6 本轮三个新产物未登记**
```
AGENT_ORCHESTRATION.md
recon/R11S_STATUS_DUALPANEL_GAP_20260901.md
recon/orchestration/LEDGER_dualpanel_20260901.md
```
→ 三者均未在 HANDOFF.md / STATUS.md 中出现。

## 文档 vs 本轮取证的对照

| # | 事实 | 判定 |
|---|---|---|
| 1 | `devices_deferred` 为空 vs 实机持续 defer | **文档错误** |
| 2 | DPU RCG warning 被定性为「不阻塞 fbcon，未查」 | **文档已过时**（已定位根因，非无害） |
| 3 | 触摸「卡在 F12 描述符，老问题」 | **文档已过时**（根因是零长读 + 无上限 defer） |
| 4 | GPU「a530_pm4.fw 缺失」 | **文档未覆盖**（另有 a530_pfp.fw、a512_zap.mbn 缺失 + 节点无 supply） |
| 5 | `CONFIG_SND_SOC_SDM660_OPPO_R11S` 未启用 | **文档未覆盖** |
| 6 | `ath10k/.../firmware-5.bin` 缺失 | **文档未覆盖** |
| 7 | 树内 R11s DTS 无显示节点 | **文档未覆盖**（仅双面板差距清单记了 G07） |
| 8 | v13 显示链打通 | **文档正确**（但支撑证据已被推翻） |

## 文档更新清单

| 路径 | 动作 | 要点 | 优先级 |
|---|---|---|---|
| `HANDOFF.md` | 追加 | v14 日期条目：问题矩阵/改进方案/合成预案三件套索引；修正 #1 定性措辞、#2 补 PDT 修复记载、#3 回滚链补 v10 | P1 |
| `STATUS.md` | 追加 | 本轮条目：联网映射结果 + 七域结论摘要 + 三份新产物 + 新产物哈希 | P1 |
| `STATUS.md` | 修订 | 6 处「设备当前态」加「（已过期，见 YYYY-MM-DD 条目）」标注 | P1 |
| `HANDOFF.md` / `STATUS.md` | 修订 | 解决 DOC2 仲裁规则歧义（建议改为：两文件冲突时以**较新日期条目**为准，并互相标注） | P1 |
| `CLAUDE.md` | 重写 §0/§4/§5/§6 | §0 当前阶段、§4 目录约定（新增 recon/v14_domains、recon/orchestration）、§5 构建原则、§6 下一步 | P2 |
| `PLAN.md` | 重排 | P0/P1/P3 勾完成；新增 P5（外设完善与主线化）；P4 细分项与实际对齐 | P2 |
| `AGENT_ORCHESTRATION.md` | 追加 | 本轮实战案例：按问题域切分的 Wave 划分、W=4 取值、两次 abort 与 Hub 兜底记录 | P2 |

## 账本结构建议（在 §11 模板基础上新增）

| 新增字段/小节 | 用途 |
|---|---|
| **置信度列**（确凿 / 高 / 中高 / 佐证级） | 区分「代码实证」「实机日志」「社区一手」「推断」 |
| **反驳证据 / 备注列** | 直接登记冲突，避免结论被静默覆盖 |
| **类别列**（P1 代码 / P2 DTB / P1 配置 / P1 日志 / 社区一手 / hash 实测） | 便于按证据强度筛选 |
| **任务表加「并发位」列** | 记录 Wave 内的实际并发槽位，便于复盘负载均衡 |
| **降级记录加「是否 Hub 兜底」列** | 已有，保留 |
| **新增「待裁决事项」小节** | 与「未取证」区分：前者需用户/实机决策，后者仅需补取证 |
| **新增「批次映射」小节** | 把每个问题映射到 v14a/v14b/v15 批次，便于跟踪落地 |

## 未取证

- `PLAN.md` 的 P2/P4 细分项与实际的偏差未逐项核对（只读了整体结构）。
- `CLAUDE.md §2` 的模型阶梯（Haiku/Sonnet/Opus）与当前可用模型的对应关系未核实。
- `recon/` 下其他历史报告（如 `R11S_PANEL_REGULATOR_DEFER_ROOTCAUSE_20260831.md`）与本轮结论的一致性未逐份复核。
