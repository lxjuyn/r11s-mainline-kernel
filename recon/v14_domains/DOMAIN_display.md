# DOMAIN_display — 显示域（DPU / 时钟 / 面板）

> Wave 1 · 子代理只读取证 · 2026-09-02 · 完整证据链见 `LEDGER_v14_20260902.md` F04-F07

## 结论

1. `update_config()` 在 `mdp_clk_src` 的 `cmd_rcgr + CMD_REG` 置 `CMD_UPDATE` 后轮询该位清零，**500 次 × `udelay(1)`（约 500µs）未清零即 WARN 并返回 -EBUSY**；这不是 M/N/D 算不出（算不出会在 `determine_rate` 阶段就 -EINVAL），而是**新父时钟没跑起来 / RCG 所在电源域未上电**。
2. 请求频率来自 `dpu_kms_init()`：`max_freq` 初始化为 `ULONG_MAX`，用 `dev_pm_opp_find_freq_floor()` 取 OPP 表最高频，然后**无条件** `dev_pm_opp_set_rate(dev, max_freq)`，且**返回值未检查** → -EBUSY 被静默吞掉。
3. **顺序问题**：`dev_pm_opp_set_rate()`（:1315）发生在 `pm_runtime_enable()`（:1324）**之前**，MMPLL5/MDSS GDSC 此时很可能未使能 → 换父后 `CMD_UPDATE` 卡住。
4. `mdp_clk_src` **没有 `CLK_SET_RATE_PARENT`**；最高频 412.5MHz 需 `P_MMPLL5`；但下游 branch **带** `CLK_SET_RATE_PARENT` → 速率请求会一路顶到 RCG 换父。
5. DPU bind 走 component 聚合，首次 probe 只注册 master，子组件未齐 → 由 `deferred_probe_work_func` 重跑才 bind（日志 3.341s）。**deferred probe 是兜回路径，但它没解决频率设置失败**——WARNING 就发生在重试路径内部。

## 证据

**轮询的位与超时判据** — `drivers/clk/qcom/clk-rcg2.c:114-138`
```c
ret = regmap_update_bits(rcg->clkr.regmap, rcg->cmd_rcgr + CMD_REG, CMD_UPDATE, CMD_UPDATE);
if (ret) return ret;
/* Wait for update to take effect */
for (count = 500; count > 0; count--) {
        ret = regmap_read(rcg->clkr.regmap, rcg->cmd_rcgr + CMD_REG, &cmd);
        if (ret) return ret;
        if (!(cmd & CMD_UPDATE)) return 0;
        udelay(1);
}
WARN(1, "%s: rcg didn't update its configuration.", name);
return -EBUSY;
```

**算不出频率会提前失败（故 WARNING ≠ 分频问题）** — 同文件 `:395-401`、`:229-284`
```c
static int clk_rcg2_determine_rate(struct clk_hw *hw, struct clk_rate_request *req)
{
        return _freq_tbl_determine_rate(hw, rcg->freq_tbl, req, CEIL);
}
...
if (clk_flags & CLK_SET_RATE_PARENT) { rate = f->freq; ... }
else { rate = clk_hw_get_rate(p); }   /* 不改父频 */
```

**目标频率来源 + 返回值被丢弃 + 顺序问题** — `drivers/gpu/drm/msm/disp/dpu1/dpu_kms.c:1301-1328`
```c
unsigned long max_freq = ULONG_MAX;
opp = dev_pm_opp_find_freq_floor(dev, &max_freq);
if (!IS_ERR(opp)) dev_pm_opp_put(opp);
dev_pm_opp_set_rate(dev, max_freq);      /* :1315 无条件，返回值未检查 */
ret = msm_kms_init(&dpu_kms->base, &kms_funcs);
...
pm_runtime_enable(&pdev->dev);           /* :1324 在 set_rate 之后才开 RPM */
```

**`mdp_clk_src` 的真实定义（不在 dtsi）** — `drivers/clk/qcom/mmcc-sdm660.c:952-976`
```c
static const struct freq_tbl ftbl_mdp_clk_src[] = {
        F(100000000, P_GPLL0_DIV, 3, 0, 0),
        F(150000000, P_GPLL0_DIV, 2, 0, 0),
        F(171428571, P_GPLL0, 3.5, 0, 0),
        F(200000000, P_GPLL0, 3, 0, 0),
        F(275000000, P_MMPLL5, 3, 0, 0),
        F(300000000, P_GPLL0, 2, 0, 0),
        F(330000000, P_MMPLL5, 2.5, 0, 0),
        F(412500000, P_MMPLL5, 2, 0, 0),
        { }
};
static struct clk_rcg2 mdp_clk_src = {
        .cmd_rcgr = 0x2040, .mnd_width = 0, .hid_width = 5,
        .parent_map = mmcc_xo_mmpll0_mmpll5_mmpll7_gpll0_gpll0_div_map,
        .freq_tbl = ftbl_mdp_clk_src,
        .clkr.hw.init = &(struct clk_init_data){
                .name = "mdp_clk_src", .ops = &clk_rcg2_ops,   /* 无 flags */
        },
};
```

**下游 branch 却带 `CLK_SET_RATE_PARENT`** — 同文件 `:2341-2346`
```c
.parent_hws = (const struct clk_hw *[]){ &mdp_clk_src.clkr.hw },
.num_parents = 1,
.flags = CLK_SET_RATE_PARENT,
.ops = &clk_branch2_ops,
```

**`&mmcc` 依赖 DSI PHY 提供时钟 → 探测顺序耦合** — `arch/arm64/boot/dts/qcom/sdm660.dtsi:296-305`
```dts
&mmcc {
        clocks = <&rpmcc RPM_SMD_XO_CLK_SRC>, <&sleep_clk>,
                 <&gcc GCC_MMSS_GPLL0_CLK>, <&gcc GCC_MMSS_GPLL0_DIV_CLK>,
                 <&mdss_dsi0_phy DSI_PIXEL_PLL_CLK>, <&mdss_dsi0_phy DSI_BYTE_PLL_CLK>,
                 <&mdss_dsi1_phy DSI_PIXEL_PLL_CLK>, <&mdss_dsi1_phy DSI_BYTE_PLL_CLK>,
```

**`&mdp` 节点无 `operating-points-v2`** — 同文件 `:204-207`
```dts
&mdp {
        compatible = "qcom,sdm660-mdp5", "qcom,mdp5";
        ports {
```

**component 聚合点** — `drivers/gpu/drm/msm/msm_drv.c:948-950, 1027, 1034-1041, 1089`
```c
drm_of_component_match_add(master_dev, matchptr, component_compare_of, intf);  /* 948 显示接口 */
drm_of_component_match_add(dev, matchptr, component_compare_of, np);           /* 1027 GPU */
ret = component_master_add_with_match(master_dev, &msm_drm_ops, match);        /* 1089 */
```

## 补丁级定位

| 项 | 位置 | 改法 | 收益 | 风险 |
|---|---|---|---|---|
| **B-1** | `dpu_kms.c:1309-1315` | set_rate 收进 `if (!IS_ERR(opp))` 分支 + 检查返回值 | 消除 ULONG_MAX 非法请求，失败可见 | 极低 |
| **B-1** | `dpu_kms.c:1315` vs `:1324` | 顺序对调：先 `pm_runtime_enable()`（必要时 get_sync）再 set_rate | GDSC 上电后 RCG 能 latch | 中：需确保 `dpu_kms->clocks` 此时已就绪 |
| **B-2** | `mmcc-sdm660.c:970-975` | 加 `flags = CLK_OPS_PARENT_ENABLE`（优先）或 `CLK_SET_RATE_PARENT` | 改频时自动 enable 父 PLL | 中：`CLK_SET_RATE_PARENT` 会牵连共用 MMPLL5 的 camss/venus |
| **B-3** | `sdm660.dtsi:204-207` | 补 `operating-points-v2`，最高频限 GPLL0 可直出档（200/300MHz） | 避开 probe 期换到未使能的 MMPLL5 | 中：频率过低可能 underflow/撕裂，须按 sofeg01_s 实际 pclk 复核 |

**`deferred_probe_timeout=30` 的定位**：应在 **cmdline** 加，不改代码默认值。但**本次 WARNING 发生在 deferred probe 重试路径内部，加超时对 D1 零收益**，只对 D6（bind 不起来）兜底。

## 未取证

1. `CMD_REG` / `CMD_UPDATE` 的宏数值（推断为 `CMD_REG 0x0`、`CMD_UPDATE BIT(0)`），需确认。
2. **DPU/mdp 的 OPP 表实际来源未取证**：dtsi 内 `&mdp` 无 opp 表，但栈证明 `_opp_config_clk_single` 真的跑到了 → 来源可能在板级 dtsi 或驱动内 `dev_pm_opp_of_add_table`。**这是 B-3 落点的前提**。
3. DPU 聚合所需完整子组件清单（可能有 HDMI/DP/WB/DSI PHY）未读全。
4. **首次 probe 失败的具体子组件未证实**：DSI PHY 依赖只是间接证据，未抓到 `-EPROBE_DEFER` 返回点。
5. MMPLL5 / MDSS GDSC 在 3.34s 的实际使能状态**未取证** → F06 的"顺序问题"目前是**最可能假设，非已证实**。
6. `deferred_probe_timeout` 在 7.0.14 的默认值未查（`drivers/base/dd.c`）。

## 与既有事实的冲突

1. **任务书前提有误**：`mdp_clk_src` 不在 `sdm660.dtsi`（grep 0 命中），实际在 `mmcc-sdm660.c:964`；dtsi 侧只通过 `&mmcc` 的 `MDP_CLK_SRC` 索引间接引用。
2. **`&mdp` compatible 是 mdp5，但日志走 DPU**：本树同时存在 mdp5 与 dpu 两套 KMS，需确认实际绑定的是哪个；否则"改 `&mdp` 节点补 OPP 表"的落点可能是错的（应改 `&dpu`）。
3. **"fbcon 能亮" vs "MDP 频率没设成功"**：不冲突但需记录——显示可用但频率不受 OPP 管控，不能据此认为显示链路已完全正常。
4. **deferred probe 解决的是"bind 起来"，不是"频率设对"**，两者不可混为一谈。
