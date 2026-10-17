# R11s 显示面板型号取证（原厂 DTS vs R11T 树内参考）

**取证日期：** 2026-08-29
**性质：** 纯只读取证 + 结论文档。未修改任何 DTS / 驱动 / config / 镜像。
**结论一句话：** OPPO R11s（OPPO 设备代号 **17011**）原厂面板是 **Samsung SOFEG01_S**（`panel-version = "SOFEG01_S"`，manufacture `samsung1024`），1080x2160（18:9）DSI **命令模式** AMOLED；**不是** R11T 的 S6E3FA3（1080x1920 16:9）。**R11T 的 s6e3fa3 驱动不得直接照抄给 R11s**——两者分辨率、物理尺寸、初始化序列、ESD 应答、背光位深全部不同，DTS/驱动证据均不支持同面板。

---

## 来源清单

| 编号 | 来源 | 说明 |
|---|---|---|
| S1 | `/home/<user>/claude/r11/r11s..dts`（17257 行，原厂 R11s DTB 反编译文本） | 主证据 |
| S2 | `/home/<user>/claude/r11/out/ref_upstream_linux-sdm660-oppor11_s`（treeless 克隆，HEAD=`edf5e0d` "Add files via upload"，origin=https://github.com/NanShengtEAM/linux-sdm660-oppor11_s）中 `HEAD:r11s.dts`，导出到 `/tmp/upstream_r11s.dts`（17376 行） | 参照（另一份反编译，面板清单与 S1 略有差异，见"已证实"第 6 条） |
| S3 | `/home/<user>/claude/r11/android_kernel_oppo_sdm660_source_d9391f88aa90/arch/arm64/boot/dts/vendor/qcom/oppo/17011.dtsi` 及同目录 `dsi-panel-oppo17011samsung_*.dtsi` | OPPO 源码 drop 中 17011 板级面板 include 链（源头级佐证） |
| S4 | `/home/<user>/claude/r11/out/linux-sdm660-oppor11-t-qcom-sdm660-7.0.y/arch/arm64/boot/dts/qcom/sdm660-oppo-r11t.dts` | R11T 树内参考 DTS（对照对象） |
| S5 | `/home/<user>/claude/r11/out/linux-sdm660-oppor11-t-qcom-sdm660-7.0.y/drivers/gpu/drm/panel/panel-samsung-s6e3fa3.c` | R11T 面板驱动模板（对照对象） |
| S6 | `/home/<user>/claude/r11/recon/p2_adb_live_dt_complete_20260730_105747/live_17011.fdt` | 实为失败采集（内容是 "cat: /sys/firmware/fdt: Permission denied"），**不含**面板证据 |
| S7 | 联网：GSMArena R11s review（https://www.gsmarena.com/oppo_r11s-review-1696.php）、Yahoo/Engadget "Oppo R11s and R11s Plus review"（https://sg.news.yahoo.com/oppo-r11s-r11s-plus-review-affordable-iphone-x-063511875.html）、TMTPost 发布报道（http://www.tmtpost.com/2890513.html）、充电头网评测（https://m.igao7.com/new...） | 仅佐证"Samsung 6.01" 2160x1080 AMOLED"，**无任何 SOFEG01/S6E 型号代码的公开资料**（多轮搜索 `"sofeg01"`、`"ams596w401"` 均无结果） |

---

## 已证实（原厂 DTS 内 R11s 面板事实，均引用行号原文）

### 1. R11s(17011) 专属面板节点 = Samsung SOFEG01_S，1080x2160 命令模式

S1 `/home/<user>/claude/r11/r11s..dts`：

```
16292:  qcom,mdss_dsi_oppo17011samsung_sofeg01_s_1080p_cmd {
16294:    qcom,mdss-dsi-panel-name = "oppo17011samsung sofeg01_s 1080p cmd mode dsi panel";
16295:    qcom,mdss-dsi-panel-manufacture = "samsung1024";
16296:    qcom,mdss-dsi-panel-version = "SOFEG01_S";
16297:    qcom,mdss-dsi-backlight-version = "SAMSUNG1024";
16298:    qcom,mdss-dsi-backlight-manufacture = "SAMSUNG1024";
16299:    qcom,mdss-dsi-panel-controller = <0x27e>;        /* 0x27e = dsi ctrl0 */
          qcom,mdss-dsi-panel-type = "dsi_cmd_mode";
16305:    qcom,mdss-dsi-panel-width = <0x438>;             /* 1080 */
16306:    qcom,mdss-dsi-panel-height = <0x870>;            /* 2160 */
          qcom,mdss-dsi-h-front-porch = <0x70>;            /* 112 */
          qcom,mdss-dsi-h-back-porch  = <0x60>;            /*  96 */
          qcom,mdss-dsi-h-pulse-width = <0x14>;            /*  20 */
          qcom,mdss-dsi-v-back-porch  = <0x04>;  v-front-porch = <0x14>;  v-pulse-width = <0x02>;
          qcom,mdss-dsi-panel-timings = <0xf03d3f00 0x6a8f3f3e 0x36030400>;
          qcom,mdss-dsi-bl-pmic-control-type = "bl_ctrl_dcs";
          qcom,mdss-dsi-bl-max-level = <0x3ff>;            /* 11-bit DCS 背光 */
          qcom,mdss-dsi-reset-sequence = <0x01 0x05 0x00 0x02 0x01 0x0c>;  /* 1-5ms-0-2ms-1-12ms */
          qcom,mdss-dsi-panel-status-command = [06 01 00 01 05 00 02 0a 08]; /* ESD 读 0x0a */
          qcom,mdss-dsi-panel-status-value = <0x9e>;       /* 期望 0x9e */
          qcom,mdss-pan-physical-width-dimension = <0x44>; /* 68 mm */
          qcom,mdss-pan-physical-height-dimension = <0x88>;/* 136 mm → 6.0" 对角 */
16369:    qcom,panel-supply-entries = <0x27d>;             /* AMOLED lab/ibb 供电组 */
```

（68x136 mm 对角 ≈ 152 mm ≈ 6.0"，与 R11s 6.01" 18:9 规格吻合；S7 联网佐证同为 Samsung AMOLED。）
无 `qcom,mdss-dsi-panel-orientation`（s6e3fa3 两个节点都有 `="180"`）。

### 2. 面板供电（phandle 0x27d = AMOLED vdda/vddio 组）

S1 行 16818-16842：`dsi_panel_pwr_supply_labibb_amoled`（phandle 0x27d）：
- `vdda-3p3`：min=max=0x2dc6c0 = 3,000,000 uV = 3.0 V
- `wqhd-vddio`：0x1b7740 = 1,800,000 uV = 1.8 V

（该 DTB 反编译中 regulator 展开为数字属性；主线移植时对应 R11T 树里 `vdda-supply`/`vddio-supply` 的角色，实际 PMIC rail 需上机核对。）

### 3. DSI 控制器与复位 GPIO

S1：

```
16593:  qcom,mdss_dsi_ctrl0@c994000 { compatible = "qcom,mdss-dsi-ctrl"; ... 0x27e = 此节点 phandle (行16620-16621) }
16611:    qcom,dsi-pref-prim-pan = <0x284>;    /* dtsi 默认值：高通参考面板 rm67195 */
16615:    qcom,platform-reset-gpio = <0x7d 0x35 0x00>;   /* 0x7d = pinctrl@03000000 (qcom,sdm660-pinctrl, 行9270-9280)；GPIO 53 */
16623:  qcom,mdss_dsi_ctrl1@c996000 { compatible = "qcom,mdss-dsi-ctrl"; ... }
16643:    qcom,dsi-pref-prim-pan = <0x292>;    /* 默认指向 oppo17021 (R11s Plus) 节点 */
16647:    qcom,platform-reset-gpio = <0x7d 0x35 0x00>;   /* 同 GPIO 53 */
```

注意：`qcom,dsi-pref-prim-pan` 只是 dtsi 兜底默认（0x284=rm67195 参考面板、0x292=17021 面板）；OPPO 4.4 内核的真正面板选择是 bootloader/运行时按面板 ID 检测完成（S3 中 `oppo/17011.dtsi` 同时编入多个面板节点即为该机制服务）。**"DTB 里有全量表"不等于"都在这台机器上"，但 17011 专属命名节点明确指认了 R11s 的面板身份。**

### 4. s6e3fa3 节点属于 R11 系（16051/16118），不属于 R11s

S1 中仅有的两个 s6e3fa3 节点：

```
16059:  qcom,mdss_dsi_oppo16051samsung_s6e3fa3_1080p_cmd {
16061:    qcom,mdss-dsi-panel-name = "oppo16051samsung s6e3fa3 1080p cmd mode dsi panel";
16063:    qcom,mdss-dsi-panel-version = "S6E3FA3";
16072/16073: width 0x438 / height 0x780            /* 1080x1920, 16:9 */

16214:  qcom,mdss_dsi_oppo16118samsung_s6e3fa3_1080p_cmd {
16216:    qcom,mdss-dsi-panel-name = "oppo16118samsung s6e3fa3 1080p cmd mode dsi panel";
16227/16228: width 0x438 / height 0x780            /* 1080x1920, 16:9 */
          qcom,mdss-dsi-panel-orientation = "180"; bl-max 0xff（8-bit）
```

两者都是 1080x1920（R11 世代 5.5" 16:9），分辨率、物理尺寸、ESD 期望值（0x9c）、背光位深与 17011 的 SOFEG01_S 节点全部不同。

### 5. R11T 对照（S4/S5）：s6e3fa3 是另一块物理面板

S4 `/home/<user>/claude/r11/out/.../sdm660-oppo-r11t.dts` 行 499-524：

```
499:  panel@0 {
500:    compatible = "samsung,s6e3fa3";
501:    reg = <0>;
502:    rotation = <180>;
505:    reset-gpios = <&tlmm 53 GPIO_ACTIVE_HIGH>;   /* 与 R11s 原厂 reset GPIO 同为 TLMM 53 */
506:    vddio-supply = <&vreg_l11a_1p8>;
507:    vdd-supply = <&vreg_l6b_3p0>;
508:    oledb-supply = <&pm660l_oledb>;
```

S5 `panel-samsung-s6e3fa3.c`：`of_match` 仅 `"samsung,s6e3fa3"`（行 371-375）；固定 mode 为 **1080x1920**、68x122 mm（行 240-256）。R11T 是 5.5" 16:9，R11s 是 6.0" 18:9——**不同面板，非同源**（同为 Samsung AMOLED 命令模式、同为 TLMM 53 复位，仅是同代平台共性）。

### 6. R11s 存在第二个面板候选变体：ams596w401（SOFEG01_S-QC01）

S2（上游参照仓库的 `r11s.dts`，与 S1 来自不同固件构建）面板清单 diff（对 S1 求差集）：

```
+ qcom,mdss_dsi_oppo17011samsung_ams596w401_1080_2280_cmd   /* 仅 S2 有 */
- qcom,mdss_dsi_oppo17081samsung_ams596w401_1080_2280_cmd   /* 仅 S1 有 */
- qcom,mdss_dsi_hx8399_truly_fhd_video                      /* 仅 S1 有 */
```

S2 行 16575-16577：
```
16575:  qcom,mdss_dsi_oppo17011samsung_ams596w401_1080_2280_cmd {
16577:    qcom,mdss-dsi-panel-name = "oppo17011samsung ams596w401 1080 2280 cmd mode dsi panel";
          qcom,mdss-dsi-panel-manufacture = "samsung1024";
          qcom,mdss-dsi-panel-version = "SOFEG01_S-QC01";   /* 见 S3 对应 dtsi */
          width 1080 / height 2280
```

S3（OPPO 源码 drop）`arch/arm64/boot/dts/vendor/qcom/oppo/17011.dtsi` 行 9-12 同时编入三份面板 dtsi，佐证 R11s 有**双面板候选**：

```
9:  #include "../dsi-panel-oppo17011samsung_sofeg01_1080p_cmd.dtsi"        /* SOFEG01_S 1080x2160 */
10: #include "../dsi-panel-oppo17021samsung_sofeg01_1080p_cmd.dtsi"        /* 17021 (R11s Plus) */
12: #include "../dsi-panel-oppo17011samsung_ams596w401_1080_2280_cmd.dtsi" /* ams596w401 1080x2280 */
行 36-47: 两面板的 PHY v2 timing 覆写与 `oppo_dsi_panel_pwr_supply_amoled` 供电组
行 117-118: synaptics 触控 `panel-x = <1080>; panel-y = <2160>;`  → 佐证整机屏为 2160 高
```

即：17011 机型至少存在 `SOFEG01_S`（1080x2160，主力）与 `ams596w401`（1080x2280，version 标 "SOFEG01_S-QC01"，manufacture 仍标 "samsung1024"）两个批量/区域变体。当前手头原厂 OTA（S1）只含 sofeg01_s 版 17011 节点；上游参照固件（S2）则两个都有。

---

## 未证实 / 待上机取证

1. **本台 R11s 实机到底装的哪个变体**（sofeg01_s 还是 ams596w401）。DTB 含全量表、选择发生在 bootloader/驱动运行时；S6 的实机 FDT 采集失败（文件内容为 `cat: /sys/firmware/fdt: Permission denied`），目前**没有任何实机活动 DT 面板证据**。
2. **SOFEG01_S 对应的三星 driver IC 精确型号**（如 S6E3FAx/S6E3FCx 系列）。联网多轮搜索（`"sofeg01"`、`"ams596w401"`、S7 各来源）均无公开型号代码；仅能确认"Samsung 6.01" 2160x1080 AMOLED"级别事实。主线上架 `panel-samsung-sofef00.c`（OnePlus 6 的 SOFE 系模块，compatible `samsung,sofef00`/`samsung,s6e3fc2x01`）是同族参照，但**命令序列必须以原厂 dtsi 为准**，不能套用 sofef00。
3. **供电 rail 与 R11T 树的 l1a/l11a/l6b/oledb 是否一一对应**（R11s 与 R11T 板载 PMIC 配置近似但未经实机验证）。

**上机取证计划（只读）：**
- 救援 shell / initramfs（root）下：`dd if=/sys/firmware/fdt` 或 `dd if=/dev/block/bootdevice/by-name/boot ...` 解包 DTB → `dtc -I dtb -O dts` → grep `oppo17011`、`panel-controller`、`dsi-pref-prim-pan`（bootloader 可能已就地改写 pref-prim-an phandle，直接看它指向哪个面板节点即可定案）。
- `/proc/cmdline` 查 `mdss-panels`/`panel_name` 相关参数；`dmesg | grep -iE 'panel|mdss dsi'` 查 `mdss_dsi_panel_init` 打印的面板名。
- `cat /sys/class/graphics/fb0/msm_fb_panel_info`（4.4 MDSS 存在此节点）可直读 panel name/panel type/ESD 信息。
- 手动 DSI 读 ID（如 0x04/0xDA/0xDB）比对原厂 dtsi 的 `panel-status-value`（sofeg01_s: 读 0x0a 期望 0x9e）。

---

## 给阶段 3 的建议

1. **驱动模板路径**：`/home/<user>/claude/r11/out/linux-sdm660-oppor11-t-qcom-sdm660-7.0.y/drivers/gpu/drm/panel/panel-samsung-s6e3fa3.c`（树内模板，结构可复用：regulator_bulk + reset + mipi_dsi 双字节 DCS 写 + 固定 mode + orientation）。
2. **新写 compatible**：建议 `samsung,sofeg01_s`（若取 ams596w401 变体则 `samsung,ams596w401`，或统一一个 compatible + 运行时 DSI ID 分流）。新文件建议 `drivers/gpu/drm/panel/panel-samsung-sofeg01_s.c`。on/off/hbm/seed/lbr 命令序列、时序（1080x2160，hfp 112 / hbp 96 / hsw 20 / vbp 4 / vfp 20 / vsw 2，DSI burst、4 lane）、ESD（读 0x0a 期望 0x9e）、DCS 背光 11-bit、复位序列 1-5ms-0-2ms-1-12ms，全部从 S3 `dsi-panel-oppo17011samsung_sofeg01_1080p_cmd.dtsi` + `oppo/17011.dtsi`（PHY v2 timing 覆写）逐条转录，不要手推。
3. **DTS 侧**（届时新写，参照 S4 的写法但换属性）：panel@0 挂 `&mdss_dsi0`，`reg=<0>`，`reset-gpios = <&tlmm 53 GPIO_ACTIVE_HIGH>`（原厂 S1 行 16615 佐证 GPIO 53 与 R11T 相同，可高置信复用），vddio/vdd/oledb 供电先按 S1 0x27d 组（3.0V vdda + 1.8V vddio）映射，rail 落点上机核对。
4. **风险清单**：
   - R11s 与 R11T 面板**不同源**（分辨率 2160 vs 1920、物理 68x136 vs 68x122 mm、ESD 0x9e vs 0x9c、背光 11-bit vs 8-bit、命令集 B0/BC/ED vs C3 系）。照抄 s6e3fa3 的初始化序列点不亮 R11s，甚至有高压误写风险。
   - 双面板变体风险：ams596w401 变体分辨率 2280、命令集不同；阶段 3 首版应**以本机取证结果为准单面板支持**，或实现按 DSI ID 的变体探测，避免写死。
   - 原厂面板为命令模式（自刷新），与树的 MDSS/DPU 驱动对接需 TE（`te-using-te-pin`）支持，注意 `mdss_te_active` pinctrl 与 S4 相同可复用。

**再次明确：R11T 的 `samsung,s6e3fa3` 驱动与 DTS 片段不得直接照抄给 R11s；除非后续上机取证显示本机实为 s6e3fa3（当前所有证据均否定这一点），否则阶段 3 必须按 SOFEG01_S（或实机测得的变体）新写 compatible 与初始化序列。**
