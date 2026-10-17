# DOMAIN_gpu — GPU 域（Adreno 512）

> Wave 2 · 子代理只读取证 · 2026-09-02 · 完整证据链见 `LEDGER_v14_20260902.md` F12、F13

## 结论

1. **DTB 里 `gpu@5000000` 节点根本没有任何 `*-supply` 属性** → `supply vdd not found` 属于「DTB 没写」，不是「名字写错」。
2. **驱动请求的 supply 名是硬编码的 `"vdd"` 和 `"vddcx"`**，对应 DT 属性必须是 `vdd-supply` / `vddcx-supply`；**adreno 目录下不存在任何 regulator 获取代码**（此前推测在 adreno 侧是错的）。
3. **`a530_pm4.fw` 是 a5xx 全家族（510/512/530/540）共用的 PM4/PFP 微码名**；SDM660/Adreno 512 条目明确请求 `a530_pm4.fw` + `a530_pfp.fw` + zapfw —— **不是驱动选错固件，是文件系统里没有**。
4. **固件清单里 `a530_pm4.fw` / `a530_pfp.fw` / `a512_zap.mbn` 三项全无** → 与 DTB `firmware-name = "a512_zap.mbn"` 构成**双重缺口**。
5. **`ops a3xx_ops` 是历史命名，不代表把 Adreno 512 当 a3xx 用**；GPU 当前真实水平是**「绑定成功、3D/渲染未初始化」**，显示能亮来自 DPU，不能当作 GPU 可用。

## 证据

**DTB GPU 节点全属性（无 supply）** — `dtb_v12.verify.dts:1498-1514`
```dts
1498: gpu@5000000 {
1499:     compatible = "qcom,adreno-512.0\0qcom,adreno";
1502:     interrupts = <0x00 0x12c 0x04>;
1504:     clock-names = "iface\0rbbmtimer\0mem\0mem_iface\0rbcpr\0core";
1505:     power-domains = <0x32 0x03>;      /* GPU GDSC */
1507:     nvmem-cells = <0x38>;  nvmem-cell-names = "speed_bin";
1509:     interconnects = <0x2a 0x01 0x2a 0x05>;
1511:     operating-points-v2 = <0x39>;
1513:     status = "okay";
1514:     phandle = <0xa8>;
```
（`:1516-1568` opp-table，最高 OPP = `opp-588000000`；`:1570-1573` zap-shader 子节点）

**zap-shader 子节点** — 同文件:1570-1573
```dts
1570: zap-shader {
1571:     memory-region = <0x3a>;
1572:     firmware-name = "a512_zap.mbn";
1573: };
```

**驱动侧的 supply 名（唯一来源）** — `drivers/gpu/drm/msm/msm_gpu.c:1050-1059`
```c
1050: /* Acquire regulators: */
1051: gpu->gpu_reg = devm_regulator_get(&pdev->dev, "vdd");
1053: if (IS_ERR(gpu->gpu_reg)) gpu->gpu_reg = NULL;
1056: gpu->gpu_cx  = devm_regulator_get(&pdev->dev, "vddcx");
1058: if (IS_ERR(gpu->gpu_cx))  gpu->gpu_cx  = NULL;
```
（dummy 返回的不是 ERR_PTR，所以 `gpu_reg/gpu_cx` 真的是 dummy 指针，后续 `enable_pwrrail()` 会走 enable 路径）

**dummy regulator 的实际用途（只 enable/disable，无调压）** — 同文件 `:26-55`
```c
30:  if (gpu->gpu_reg) { ret = regulator_enable(gpu->gpu_reg); ... }
38:  if (gpu->gpu_cx)  { ret = regulator_enable(gpu->gpu_cx);  ... }
49:  static int disable_pwrrail(struct msm_gpu *gpu)
51:  if (gpu->gpu_cx)  regulator_disable(gpu->gpu_cx);
53:  if (gpu->gpu_reg) regulator_disable(gpu->gpu_reg);
```
→ **全树 msm 目录内无 `regulator_set_voltage` 用于 GPU**，upstream 从不给 GPU 调压，电压由 OPP/opp-level + GDSC perf state 承担。

**a5xx 512 条目与固件名** — `drivers/gpu/drm/msm/adreno/a5xx_catalog.c:110-134`
```c
110: .chip_ids = ADRENO_CHIP_IDS(0x05010200),
112: .revn = 512,
113: .fw = {
114:     [ADRENO_FW_PM4] = "a530_pm4.fw",
115:     [ADRENO_FW_PFP] = "a530_pfp.fw",
116: },
117: .gmem = (SZ_256K + SZ_16K),
125: .zapfw = "a512_zap.mdt",
131:     {135, 4},  /* up to 647 MHz */
```
（510/530/540 条目同样用 `a530_pm4.fw`/`a530_pfp.fw`，见 `:98-101` / `:142-145` / `:161-163`）

**固件加载是 3D 初始化的前置** — `drivers/gpu/drm/msm/adreno/adreno_device.c:86-99`
```c
92:  ret = adreno_load_fw(adreno_gpu);
93:  if (ret)
94:      return NULL;          /* GPU 3D 初始化在此终止 */
...
267: static const struct component_ops a3xx_ops = { .bind = adreno_bind, };
```

**zap shader 走 DT 的 firmware-name（.mbn 直取）** — `adreno_gpu.c:48-49, 75-78, 178-184`
```c
48:  np = of_get_child_by_name(dev->of_node, "zap-shader");
49:  if (!of_device_is_available(np)) { ... return -ENODEV; }
75:  of_property_read_string_index(np, "firmware-name", 0, &signed_fwname);
76:  if (signed_fwname) { fwname = signed_fwname;   /* "a512_zap.mbn" */
78:      ret = request_firmware_direct(&fw, fwname, gpu->dev->dev); }
178: /* We need SCM to be able to load the firmware */
179: if (!qcom_scm_is_available()) { ... return -EPROBE_DEFER; }
```

**固件清单核对（控制组验证结果可信）**
```
search_file "a5*" recursive = true  →  0 个文件
    ⇒ a530_pm4.fw 无、a530_pfp.fw 无、a512_zap.mbn 无
控制组 search_file "*.mdt"  →  命中 5 个
    （modem.mdt、qcom/sdm660/adsp.mdt、cdsp.mdt、venus.mdt、ath10k/.../wlanmdsp.mdt）
    ⇒ 证明目录可枚举，上一条 0 命中是「真缺失」而非工具失效
```

**DTB 中真实存在的电源资源（无可用 phandle）** — 同 DTS:437-455、1846-1848、1962-1964
```dts
437: regulators-0 { compatible = "qcom,rpm-pm660l-regulators";
450:     bob { regulator-min-microvolt = <0x325aa0>; ... phandle = <0x1e>; };
457:     s1 { regulator-min-microvolt = <0x112a88>; ... };   /* 无 phandle = 未被引用 */
```
- SPMI 侧 `pm660-regulators`（`:1846-1848`）与 `pm660l-regulators`（`:1962-1964`）**均为空节点、无子节点**
- 唯一带 phandle 的 RPM regulator 是 `bob = <0x1e>`（3.3V 域，**不可用作 GPU vdd**）

## 补丁级定位

| 项 | 位置 | 改法 | 收益 | 风险 |
|---|---|---|---|---|
| **B-4（最高风险）** | 手术 DTS 的 `gpu@5000000` | 加 `vdd-supply` / `vddcx-supply`；**禁止**写成 `vddgpu-supply`（驱动不认） | dummy 消失 → 真正控制上电/下电，runtime suspend 可省电 | **本次最高风险**：指错电源域 → `regulator_enable()` 失败 → GPU 从"能绑定无 3D"退化为"完全不初始化"；共享轨还可能连带关别人的电。**必须单独出包 + 保留回滚** |
| **B-5（低风险）** | `/lib/firmware/qcom/` | 放 `a530_pm4.fw` + `a530_pfp.fw`（linux-firmware 或 `firmware-qcom-adreno-a530` 包） | 解除 `adreno_load_fw()` 失败 → 3D 初始化得以继续 | 低（纯加文件）；只放 `qcom/` 一处，勿与根路径重复 |
| C-2（v15） | `/lib/firmware/a512_zap.mbn` | 取 `a512_zap.mbn`（签名整包），**路径与 DTB 名字严格一致** | ZAP 加载成功，a5xx 才能进入受保护渲染 | 中：缺失/签名不匹配 → SCM 失败或 GPU hang；`.mbn` 与 `.mdt` 混放易误判 |

**B-4 的关键障碍（已取证）**：当前 DTB 里**没有现成可用 phandle**，需先在 dtsi 中为 GPU 供电轨加 phandle 标签再引用；`vddcx` 属 RPM corner 电源，若 upstream 树无对应 regulator 节点，**建议先留空保持 dummy，不要瞎指**。

**附带建议**：若 v14 暂不接真实 regulator，把最高 OPP 限制到已验证频率，避免无调压状态下顶频（588MHz）运行。

## 未取证

1. **GPU vdd/vddcx 应指向的具体 phandle 未取证**：只确认 pm660/pm660l 的 `regulators` 节点为空、rpm-pm660l 子项中除 `bob` 外无 phandle；「谁是 gfx 轨」未逐项解析（未读 437-700 全段）。
2. **未验证 v13 实机是否真有 `/dev/dri/card0`**：按上游逻辑 `adreno_load_gpu()` 返回 NULL 后 drm 设备应注册失败，但未核对 dmesg 中是否有 card0/渲染节点相关行。
3. **`a512_zap.mbn` 的官方来源未定位**；`firmware_inventory` 是否为设备全量 `/lib/firmware` 快照亦未证实。
4. **RPM 侧 corner regulator（vddcx）在此 DTB/内核中是否有对应节点未确认**：全 DTB 只有 6 个 `regulator-name`（usb_otg_vbus/oledb/vph_pwr/lcdb/disp_vddts_vreg/touchpanel_vdd），均非 GPU cx。
5. 顶频运行的实际热/稳定性影响**需实测**（红外/热日志/hang 计数），本次未取证。

## 与既有事实的冲突

1. **「dummy regulator = 频率失控/过热」的直觉 vs 代码事实**：`msm_gpu.c:26-56` 只做 enable/disable，**全树 msm 目录无 GPU 调压调用** → dummy 不会造成超频失控；真实影响是「无法调压 + 无法断电轨」，顶频长期运行存在欠压不稳风险。
2. **社区「GPU Partial，KMS/fbcon OK」vs v13 日志序列**：`:566` 显示 `bound 5000000.gpu`，但 `:623-624` 显示 a530_pm4.fw 加载失败且 `adreno_device.c:93-94` 会 `return NULL`。**双方证据并列**：
   - 代码侧：`adreno_device.c:92-94` → 固件失败即终止 3D 初始化
   - 日志侧：绑定（`:566`）与固件（`:623`）是**两阶段**，绑定成功 ≠ 3D 初始化成功
   → 用户观察到的「显示能亮」很可能与 GPU 3D 无关，**v14 必须先裁决此点**。
3. **`ops a3xx_ops` 字面 vs 实际**：不构成「把 512 认成 a3xx」的缺陷，以 catalog 匹配结果为准。**不要为此改驱动**。
4. **DTB zap-shader 用 `.mbn`（`:1572`）vs catalog 用 `.mdt`（`a5xx_catalog.c:125`）**：并存但不冲突——adreno_gpu.c:75-83 优先用 DT 的 `firmware-name`（.mbn，direct 路径），.mdt 仅作回退。**补丁时不要把 DTB 改成 `.mdt`**，除非手上只有 `.mdt`。
