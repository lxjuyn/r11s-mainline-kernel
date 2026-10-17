# DOMAIN_dsi_clk — V1 pclk0_clk_src 修复定位（Wave A · 2026-09-02）

> 子代理只读审计 · 完整证据链见提交记录。任务书与结论已交叉核对 v14b 实机日志 `:586-680`。

## 结论

1. `pclk0/pclk1_clk_src`（`mmcc-sdm660.c:984/998`）与 `mdp_clk_src` 结构不同：**无 freq_tbl**、`clk_pixel_ops`（MND 小数分频）、父时钟 = DSI PHY PLL（`dsi0pll`/`dsi1pll`）、flags 仅 `CLK_SET_RATE_PARENT | CLK_GET_RATE_NOCACHE`——**无 `CLK_OPS_PARENT_ENABLE`**。
2. 根因 = **结构性顺序**：DSI 所有路径都是先 `link_clk_set_rate`（重配 pclk RCG）后 `link_clk_enable`（才沿 CCF 链触发 `dsi0vco_clk.prepare` → PLL_CNTRL=1 + lock）。set_rate 时 PLL 未起振 → `CMD_UPDATE` 无源时钟不自清 → `clk-rcg2.c:136` WARN（`update_config` 500×1µs 超时）。
   - 路径 A：`dsi_manager.c:223/227 → dsi_host.c:2480 set_rate → :2482 enable`（失败会中止 power_on）
   - 路径 B：`dsi_host.c:2145-2146`（xfer_prepare，**set_rate 返回值被忽略**）
3. 修复首选（与已验证的 mdp 修复同构）：两处 `flags` 加 `CLK_OPS_PARENT_ENABLE` —— CCF 在 set_rate 前沿父链 prepare/enable 到 dsi0vco_clk，PLL 起振后 CMD_UPDATE 正常自清。
4. byte0/byte1_clk_src 同构但 SDM660 的 6g 路径不对 byte 调 `clk_set_rate`（走 OPP vote）→ 解释日志只有 pclk0 报警。
5. 风险：每次 set_rate 多一轮 PLL prepare/unprepare（lock 轮询 ≤2×15ms）；若 xfer 路径在 vcca 未开时触发，WARN 会变成显式 `DSI PLL lock failed`（可见性更好）。若实机出现该行，再叠 DSI 侧补丁（`dsi_host.c` xfer_prepare 前置 power_on）。

## 补丁级定位

| 项 | 位置 | 改法 |
|---|---|---|
| V1 | `mmcc-sdm660.c:994`（pclk0）、`:1008`（pclk1） | flags 加 `CLK_OPS_PARENT_ENABLE` |

## 实机验证关键字（明早）

- `pclk0_clk_src: rcg didn't update` 应**消失**
- 不应出现 `DSI PLL lock failed`（若出现 → 叠加路径 B 补丁）
- 显示仍亮（card0 / msmdrmfb / panel prepare 正常）
