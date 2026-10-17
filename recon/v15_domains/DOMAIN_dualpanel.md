# DOMAIN_dualpanel — 双面板自动检测实施设计（Wave A · 2026-09-02）

> 子代理只读审计 + v14b 实机 cmdline 证据交叉。原厂机制优先（CLAUDE.md 取证优先级）。

## 关键事实（推翻原设想）

1. **probe 阶段 DCS 读不可行**：`dsi_host.c:1742` 硬性要求 `msm_host->power_on`，而它只在 bridge pre_enable 链置位。ID 读唯一可行时机 = `prepare()` 内（v13 实机已证 prepare 中 `0x0a` 读成功）。
2. **graph 是单选结构**：`dsi.c:131` `devm_drm_of_get_bridge(node,1,0)` 只解析 port@1/ep0；graph 指向的 panel 未注册 → `-EPROBE_DEFER` 死循环，显示永久起不来。**单纯双开 + -ENODEV 让位会打碎显示**。
3. **panel@1 `reg=<0x01>` = VC1**；改 `<0x00>` 会与 panel@0 产生同名 device（`-EEXIST`）。
4. **VC 覆盖坑**：两个 panel 都 `mipi_dsi_attach` 时，后者覆盖 `msm_host->channel`（`dsi_host.c:1708-1711`）→ panel@0 的传输会打到 VC1 失效。**必须只让被选中的面板 attach**。
5. **原厂自动检测机制已在 cmdline**：ABL 传 `mdss_mdp.panel=1:dsi:0:qcom,mdss_dsi_oppo17011samsung_sofeg01_s_1080p_cmd:config0:...`（v14b 实机 `:3`）——**LK 已检测面板并把名字传给内核**，这就是本机原厂"自动切换"的实现层。
6. 供电/reset/pinctrl phandle 两面板完全相同（共享合法），双开唯一要补的 = panel@1 status + port/endpoint + dsi 侧第二 endpoint。
7. prepare 前置 ID 判别寄存器无一手证据（0x0a 的期望值是 init 后 ESD 态）→ **不做 prepare 前置硬判**，只留 cmdline 门控 + 日志。

## 实施设计（三层，全部最小 diff）

| 层 | 位置 | 改法 |
|---|---|---|
| ① 驱动门控 | `panel-samsung-sofeg01-s.c` / `panel-samsung-ams596w401.c` probe 开头 | 解析 `saved_command_line` 的 `mdss_mdp.panel=`：无该参数 → 仅 VC0（panel@0）通过（保持 v14 行为）；有 → 仅 cmdline 含本面板 token（`sofeg01`/`ams596`）者 `mipi_dsi_attach`，其余 `return -ENODEV`（兄弟设备不受影响，`drm_mipi_dsi.c:331-348`） |
| ② 桥选择 | `dsi.c:131` dsi_bind | cmdline 有 `mdss_mdp.panel=` 时改为遍历 port@1 的 endpoints：`of_graph_get_remote_node` → `of_drm_find_panel`（未注册=被门控，跳过不 defer）→ 按 compatible/token 匹配选中；无匹配回落首个已注册面板；cmdline 无参 → 走原 `devm_drm_of_get_bridge`（行为不变） |
| ③ DTB | 手术 dtb_v15 | panel@1 删 `status="disabled"` + 补 port/endpoint（phandle）；dsi port@1 原 ep 补 `reg=<0>`、新增 ep `reg=<1>` 指向 panel@1 |

## 验证边界（诚实声明）

- 本机（sofeg01 变体）明早可验证：sofeg01 被选中、ams596 被 -ENODEV 门控、显示正常、无 VC 覆盖。
- ams596 命中路径需 2280/另一变体实机，本轮不可验证（C-4 保留项）。
- ams596 的 ABL token 假设为 `ams596` 子串（无实机 cmdline 样本，属推断；sofeg01 的为实机证据）。
