# R11s v14 改进方案（补丁级定位）

> 生成：2026-09-02 · 基线 v13 实刷镜像 · 配套：`R11S_V14_ISSUE_MATRIX_20260902.md`（问题清单与证据）
> 每个改动精确到 `文件:行号`，含改法、预期收益、风险、验证方法。
> **未经用户当次确认，不得执行任何触设备动作。**

---

## 一、分批策略

| 批次 | 定位 | 纳入原则 | 建议 |
|---|---|---|---|
| **v14a** | 止血 | 低风险 + 高收益 + 不改硬件语义 | **全部纳入**，与切根同批验证 |
| **v14b** | 根治 | 触及电源域/时钟/供电，有误伤风险 | 单独出包、单独验证、保留回滚 |
| **v15** | 深水区 | 需外部固件源或跨子系统重构 | 本轮只做定位，不动手 |

---

## 二、v14a —— 止血（低风险高收益，建议全纳入）

### A-1【治本】修 rmi4 描述符零长读
- **问题**：T1（F12 Control 描述符读回全 0 → `size_presence_reg==0` → 零长读 → -95）
- **位置**：`drivers/input/rmi4/rmi_driver.c:877`、`:887`
- **改法**：
  ```c
  /* :877 — 删除死代码 `size_presence_reg <  ||`（u8 恒假），并补判 0 */
  if (size_presence_reg > 35)
          return -EIO;
  /* :887 前插入 */
  if (size_presence_reg == 0)
          return -ENODEV;   /* RMI4 规范：size 为 0 即该描述符不存在 */
  ```
- **预期收益**：-95 与每轮 200ms 徒劳重试立即消失；f12 拿到确定错误码，后续策略才有意义。
- **风险**：影响所有 Fxx 描述符解析（F11/F1A/F34 同走此函数）。`size==0` 按规范即"无该描述符"，返回 `-ENODEV` 语义正确。
- **验证**：dmesg 中 `adapter quirk: no zero length` 应消失；F12 报 `-ENODEV` 而非 `-5`。

### A-2【刹车】给 f12 probe 加全局失败上限
- **问题**：T2/T4/T5（无限 defer 循环，独占 `deferred_probe_work`，占空比 82–96%）
- **位置**：`drivers/input/rmi4/rmi_f12.c:470 / 480 / 490`（三处 `return -EPROBE_DEFER;`）
- **改法**（文件作用域，宏定义附近加）：
  ```c
  #define RMI_F12_MAX_DESC_DEFERS 3
  static int rmi_f12_desc_defer_count;
  static bool rmi_f12_desc_gave_up;

  static int rmi_f12_desc_fail(struct rmi_function *fn, const char *what, int ret)
  {
          if (++rmi_f12_desc_defer_count < RMI_F12_MAX_DESC_DEFERS) {
                  dev_err(&fn->dev, "%s Register Descriptor unreadable (%d), deferring probe (%d/%d)\n",
                          what, ret, rmi_f12_desc_defer_count, RMI_F12_MAX_DESC_DEFERS);
                  return -EPROBE_DEFER;
          }
          if (!rmi_f12_desc_gave_up) {
                  rmi_f12_desc_gave_up = true;
                  dev_err(&fn->dev, "%s Register Descriptor unreadable (%d) after %d probes: giving up, F12 disabled\n",
                          what, ret, rmi_f12_desc_defer_count);
          }
          return -ENODEV;   /* 关键：不再 defer，循环终止 */
  }
  ```
  三处出口改为 `return rmi_f12_desc_fail(fn, "Query"|"Control"|"Data", ret);`
- **预期收益**：最多 3 轮（约 2.5s）后彻底停止；`deferred_probe_work` 解除占用；日志从"无限刷屏"变 ≤3 条。配合 A-1 通常第 1 轮即定案。
- **风险（必须复核）**：返回 `-ENODEV` 后 `fn12` **仍留在 `data->function_list`** 且其 irq 位已在 `rmi_driver.c:1186/1208` 置位，而 f12 私有数据随 probe 失败被 devres 释放 → 若 F12 的 IRQ 已使能，存在 `rmi_f12_attention()` 拿到空 drvdata 的风险。**本次未读该函数，实施前必须先复核**；稳妥做法是在放弃路径同时清 irq 位（如 `drv->clear_irq_bits(fn->rmi_dev, fn->irq_mask)`）或把 fn 摘出 `function_list`。
- **验证**：dmesg 中 `deferring probe` 出现次数 ≤3；`cat /sys/kernel/debug/devices_deferred` 不再有 `rmi4-00.fn12`。

### A-3【清理】传输层拒绝零长读 + 确定性错误不重试
- **问题**：T3（对 -EOPNOTSUPP 仍重试 10 次 × 24ms）
- **位置**：`drivers/input/rmi4/rmi_i2c.c:198`（retry 循环入口）、`:207-210`
- **改法**：
  ```c
  if (!len) return -EINVAL;                       /* :198 之前，永不发零长读 */
  ...
  if (retval == -EOPNOTSUPP || retval == -EINVAL) /* 循环内，确定性错误立即 break */
          break;
  ```
- **预期收益**：每轮省 2×200ms 无意义睡眠，日志噪声减半。
- **风险**：极低。需确认无调用者依赖"len=0 返回 0"的语义（本树内未见）。
- **验证**：`rmi_i2c_read_block: read failed, retry N` 不再成串出现。

### A-4【开配置】启用 R11s 专用音频 machine driver
- **问题**：A1（`CONFIG_SND_SOC_SDM660_OPPO_R11S` 未启用，源码存在但不编译）
- **位置**：`build/r11s_phase2/.config:4469`（`is not set`）→ 改 `=y`；同步回写 `arch/arm64/configs/r11s_defconfig`（当前**完全缺失**该符号）
- **改法**：两处置 `CONFIG_SND_SOC_SDM660_OPPO_R11S=y`；改完须 `savedefconfig` 回写保持 defconfig/.config 一致（沿用 v12 的既有做法）。
- **预期收益**：R11s 专用 machine driver 进入内核，声卡 probe 才可能成功。
- **风险**：低（只是编译开）。但若该驱动与 `sdm660-internal.c` 争抢同一 compatible，需先确认二者是否互斥——**实施前先读 `sdm660-oppo-r11s.c` 的 of_match 表**。
- **验证**：`dmesg | grep -i snd` 出现声卡注册；`aplay -l` 有设备。

### A-5【固件路径】安装 WiFi 固件到驱动请求路径
- **问题**：W1/W2（`ath10k/WCN3990/hw1.0/firmware-5.bin` 缺失，原厂 mbn 孤立在 `archive/`）
- **位置**：固件清单 `firmware/ath10k/WCN3990/hw1.0/`（新增文件）；驱动请求见 `ath10k/hw.h:125,138` + `core.c:1325`
- **改法**：把 `firmware/archive/wlanmdsp.mbn` **另存副本**为 `ath10k/WCN3990/hw1.0/firmware-5.bin`（保留 `archive/` 原件不删）。
- **⚠ 前置（必须先做 A-6）**：不要直接假设该 mbn 版本可用。
- **预期收益**：消除路径硬不匹配，否则 ath10k_snoc 必然 probe 失败。
- **风险**：无变砖风险；版本不对则进入 W3 场景。

### A-6【取证·不改文件】核对 wlanmdsp 版本，裁决 W3
- **问题**：W3（社区实测原厂 1.0.0.533 / htt-ver 3.50 会 fatal error）
- **命令（只读）**：
  ```bash
  cd /home/<user>/claude/r11/backups/firmware_inventory_r11s_20260830_043151/firmware
  strings -n 6 archive/wlanmdsp.mbn | grep -iE '1\.0\.0\.[0-9]{3}|htt-ver|WLAN\.RTF' | sort -u
  sha1sum archive/wlanmdsp.mbn
  ```
- **判定线**：
  - 输出 `1.0.0.533` / `htt-ver 3.50` → **必须**执行整组替换（A-7）
  - 输出 `≥1.0.0.591` / `htt-ver ≥3.58` → 可直接用（A-5 即可）
- **风险**：无。这是把"概率风险"变成"确定结论"的关键一步，**必须在 v14 上板前完成**。

### A-7【条件触发】整组替换 modem/WiFi 固件
- **触发条件**：A-6 判定命中旧版本
- **改法**：取 **whyred V12 的 NON-HLOS.bin**，解包后**整组替换**：`wlanmdsp.mbn`、`mba.mbn`、`modem.b*`、`qcom/sdm660/adsp.b*`、`qcom/sdm660/cdsp.b*`
- **依据**：`[联网·佐证级]` jason 移植报告 §12.1——wlanmdsp 与 modem 组件强耦合，单换会触发 modem watchdog timeout
- **风险**：误配版本 → modem watchdog timeout（不砖，可覆盖 `/lib/firmware` 恢复）

### A-8【固件补包】救援 ramdisk 补 BT 固件
- **问题**：W4（`qca/crbtfw21.tlv` 在救援 ramdisk 加载 -2，路径正确但未打包）
- **位置**：救援 ramdisk 的 `/lib/firmware` 打包清单
- **改法**：加入 `qca/crbtfw21.tlv`（113,976 B）+ `qca/crnv21.bin`（4.39 KB）
- **预期收益**：BT 在切根前即可用。
- **风险**：ramdisk 体积 +116KB（可接受）。**注意**：adsp/cdsp 共约 20MB 级，不建议全塞进 ramdisk（会顶到 64MB boot 上限），留给 rootfs v3。
- **验证**：`dmesg | grep -i bluetooth` 不再有 `-2`。

### A-9【打包参数】v14 合成时逐项显式传参
- **问题**：B2（`r11s_bootimg_pack.py` 的 CANON 默认值与 v13 既有事实冲突）
- **位置**：`tools/r11s_bootimg_pack.py:22-37`
- **改法**：合成时**必须**显式传 `--base 0x80000000 --kernel-offset 0x8000 --ramdisk-offset 0x3000000 --tags-offset 0x100 --pagesize 0x1000 --os-version 0x12000139 --header-version 1`，不可依赖脚本默认值。
- **风险**：不传则产出的 header 与 v13 不一致，可能被 ABL 拒。
- **验证**：出包后 header 逐字段与 v13 对比，唯一差异应为 kernel/ramdisk size。

---

## 三、v14b —— 根治（中风险，建议单独出包验证）

### B-1【DPU 时钟】修 `dpu_kms_init` 的 set_rate 调用
- **问题**：D2/D3（无条件 `set_rate(ULONG_MAX)` + 返回值未检查 + 顺序早于 `pm_runtime_enable`）
- **位置**：`drivers/gpu/drm/msm/disp/dpu1/dpu_kms.c:1309-1315`、`:1324`
- **改法**：
  1. 把 `dev_pm_opp_set_rate()` 收进 `if (!IS_ERR(opp))` 分支，并**检查返回值**（当前被静默吞掉）；
  2. 顺序对调：先 `pm_runtime_enable(&pdev->dev)`（必要时 `pm_runtime_get_sync()`），**再** `dev_pm_opp_set_rate()`。
- **预期收益**：MDSS GDSC / 核心时钟上电后再动 RCG，`CMD_UPDATE` 能自清 → MDP 时钟频率真正生效；失败也可见。
- **风险**：中。RPM 提前启用需确保 `dpu_runtime_resume` 依赖的数据结构（`dpu_kms->clocks` / `num_paths`）此时已就绪；可能需移到 `msm_kms_init` 之后再 `get_sync`。
- **验证**：`mdp_clk_src: rcg didn't update its configuration` 消失；`cat /sys/kernel/debug/clk/clk_summary | grep mdp` 确认频率已变。

### B-2【DPU 时钟】给 `mdp_clk_src` 补时钟 flag
- **问题**：D5（`mdp_clk_src` 无 `CLK_SET_RATE_PARENT` / `CLK_OPS_PARENT_ENABLE`，最高频 412.5MHz 需 MMPLL5）
- **位置**：`drivers/clk/qcom/mmcc-sdm660.c:970-975`（`mdp_clk_src` 的 `clk_init_data`，当前无 flags）
- **改法**：加 `flags = CLK_OPS_PARENT_ENABLE`（**优先**，代价小）或 `CLK_SET_RATE_PARENT`。
- **预期收益**：改频时内核自动 enable 父 PLL，RCG 有源时钟后能 latch。
- **风险**：中。`CLK_SET_RATE_PARENT` 会允许改 MMPLL5 频率，而 MMPLL5 被 camss/venus/MMSS 其他分支共用，可能牵连摄像头/视频；与上游 mmcc-sdm660 现状不一致，**需回归测试**。

### B-3【DPU 时钟】补 `&mdp` 的 OPP 表（保守档位）
- **问题**：D4（`&mdp` 缺 `operating-points-v2`，但调用栈证明 OPP 表确实存在，来源待查）
- **位置**：`arch/arm64/boot/dts/qcom/sdm660.dtsi:204-207`
- **改法**：补 `operating-points-v2`，最高频**限定在 GPLL0 可直出的档位**（如 200/300 MHz），避开需 MMPLL5 的 275/330/412.5 MHz。
- **风险**：中。频率过低可能在所配面板像素时钟下 underflow/撕裂，**须按 sofeg01_s 的实际 pclk 复核**。
- **前置**：先查清当前 OPP 表究竟来自哪里（板级 dtsi 还是驱动内 `dev_pm_opp_of_add_table`），否则落点会错。

### B-4【GPU】补 GPU 供电属性（**本次最高风险项**）
- **问题**：G1（`gpu@5000000` 完全无 `*-supply`）
- **位置**：手术 DTS 的 `gpu@5000000` 节点（对应 `dtb_v12.verify.dts:1498-1514`）；驱动请求名见 `drivers/gpu/drm/msm/msm_gpu.c:1051`（`"vdd"`）、`:1056`（`"vddcx"`）
- **改法**：在 `status = "okay"` 前插入 `vdd-supply = <&xxx>;` 与 `vddcx-supply = <&yyy>;`。
- **⚠ 关键障碍（已取证）**：**当前 DTB 里没有现成可用 phandle**——`rpm-pm660l-regulators`（`:437` 起）子项中除 `bob = <0x1e>` 外均无 phandle；`pm660` / `pm660l` 的 `regulators` 节点（`:1846-1848`、`:1962-1964`）为空无子节点。需先在 dtsi 中为 GPU 供电轨加 phandle 标签再引用。
- **建议**：`vddcx` 属 RPM corner 电源，若 upstream 树无对应 regulator 节点，**先留空保持 dummy**，不要瞎指。
- **预期收益**：dummy 消失 → `enable_pwrrail()`（`msm_gpu.c:26-56`）真正控制 vdd_gfx 上电/下电，runtime suspend 能关轨省电。
- **风险**：**最高**。指错电源域或电流不足 → `regulator_enable()` 失败 → GPU 从"能绑定但无 3D"退化成"完全不初始化"；若该轨被其他消费者共享，GPU 侧 disable 可能连带关掉别人的电。**必须单独出包 + 保留回滚镜像**。

### B-5【GPU】放入 a530 微码
- **问题**：G2（`a530_pm4.fw` / `a530_pfp.fw` 缺失）
- **位置**：`/lib/firmware/qcom/a530_pm4.fw`、`/lib/firmware/qcom/a530_pfp.fw`（`adreno_request_fw()` 先查 `qcom/` 前缀，见 `adreno_gpu.c:522-601`；日志报错路径即 `qcom/a530_pm4.fw`）
- **来源**：linux-firmware 仓库的 `qcom/a530_pm4.fw`、`qcom/a530_pfp.fw`（或 Debian `firmware-qcom-adreno-a530` 包）
- **预期收益**：解除 `adreno_load_fw()` 失败（`adreno_gpu.c:621-623`）→ GPU 3D 初始化得以继续。
- **风险**：低（纯加文件）。只放 `qcom/` 一处即可，勿与根路径重复。

---

## 四、v15 —— 深水区（本轮只定位，不动手）

| ID | 事项 | 阻塞点 | 何时可做 |
|---|---|---|---|
| C-1 | 音频 internal MI2S 端口核对（`sound/soc/qcom/qdsp6/q6afe-dai.c`、`q6dsp-lpass-ports.c` 逐个打开核实） | A4 未取证；port id 错 = 无声/串道 | v15 |
| C-2 | `a512_zap.mbn` 获取与安放（G3） | 外部固件源未定位；与 SCM 调用耦合 | v15 |
| C-3 | 树内 R11s DTS 显示链回写（D7），结束"手术 DTB 双轨" | 跨子系统重构，需完整回归 | v15 |
| C-4 | 双面板真正兼容（ID 探测 + 2280 变体实机） | 需另一台变体实机 | 目标明确后再做 |
| C-5 | GPU 顶频 OPP 限制（G5） | 需先有真实供电（B-4） | B-4 之后 |

---

## 五、明确**不建议**做的（误伤风险 > 收益）

| 事项 | 为什么不做 |
|---|---|
| 把 codec compatible 改成上游 PM660L / SDM660 | 树内已有下游别名 `qcom,pmic-analog-codec` / `qcom,msm-digital-codec` 覆盖实刷 DTB，改了反而失效（A5） |
| 照抄社区教程给 modem 固件加 `qcom/sdm660/` 前缀 | 本 DTB 的命名与清单布局**已一致**，加前缀会引入新 ENOENT |
| 把 DTB 的 `a512_zap.mbn` 改成 `.mdt` | `.mbn` 走 direct 路径，是正确写法；只有手上无 `.mbn` 时才回退 `.mdt` |
| 因为日志出现 `ops a3xx_ops` 就去改 adreno 驱动 | `find_chipid()` 已正确命中 `a5xx_catalog.c:110` 的 512 条目，不是 bug |
| 复刷 v12 验证"面板 defer 竞态" | 只能证明竞态存在，解决不了任何问题；而 D1-D3 已给出可修的具体代码点，性价比低 |
| 把 adsp/cdsp 全量固件塞进救援 ramdisk | 约 20MB 级，会顶到 64MB boot 上限；留给 rootfs v3 |

---

## 六、v14 上板验证清单（对应 B1 的"7 个提交未上板"）

优先复核以下未验证改动，逐项给日志关键字：

| 未验证提交 | 内容 | v14 dmesg 关键字 |
|---|---|---|
| `ddff10388` | audio v11 全内置 + glue 禁用 + 候选 DTB | `snd` / `sdm660-int-sndcard` / `audio-codec` |
| `d947f542d` | v9 四路集成（触摸/音频/电池/无线） | `qcom_smbx` / `battery` / `ath10k` |
| `476821c28` | rmi4 F12 描述符读取加固 | `Register Descriptor` |
| `a02aced7f` | rmi4 PDT 校验与重复位 | `PDT` / `re-reset` |
| `b55601e7d` | rmi4_i2c 厂商对齐重试 | `rmi_i2c_read_block` |
| `e520efd19` | rmi4_i2c 供电请求 + OLEDB=y | `supply` / `OLEDB` |
| `ce07c13f5` | SOFEG01_S 面板驱动 + DRM_MSM 内置 | `panel-samsung-sofeg01-s` / `power mode` |
| `11bf7be6f` | rmi4 容忍重复/损坏 PDT 条目 | `duplicate` / `EEXIST` |

**另需新增确认（本轮新发现）**：
- `remoteproc0` / `mss` 的固件加载行（W6：WiFi 依赖 modem DSP）
- `mdp_clk_src` 是否还有 RCG warning（D1-D3 是否生效）
- `a530_pm4.fw` 是否加载成功（B-5）
- `firmware-5.bin` 是否加载成功（A-5）
- **触摸**：`deferring probe` 出现次数应 ≤3（A-2 是否生效）
- **冷启动约束**：QMI 协商需冷启动，禁止 warm reboot 后判定 WiFi 成败

---

## 七、文档同步（配合 v14）

按 `recon/v14_domains/DOMAIN_docs.md` 的清单执行，要点：
1. `HANDOFF.md` 追加 v14 日期条目 + 修正 DOC1/DOC3 的 6 处不一致；
2. `STATUS.md` 追加本轮条目（联网映射 + 七域结论摘要）；
3. 解决 DOC2 的仲裁规则歧义（当前"以 STATUS 为准"是 HANDOFF 单向声明，STATUS 从未声明自己权威）；
4. `STATUS.md` 的 6 处"设备当前态"需加过期标注，否则 append-only 结构下无法判断哪个是最新。
