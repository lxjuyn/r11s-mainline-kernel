# R11s 音频 DTB 手术候选件（AUDIO_DTB_SURGERY_CANDIDATE）

- 日期：2026-08-30　任务：#32　执行：主机侧纯分析，**未触碰设备、未改适配树源码、未动现行镜像/原件**
- 基线：`out/v9_dtb/dtb_v9.dtb`（64,521 B，sha256 `b6fce4bb…`，现行权威，未修改）
- 候选件：`out/v9_dtb/dtb_v9_audio_candidate.dtb`（64,564 B，sha256 `1f2ac674…`，见 §5）
- 逐行 diff 留档：`recon/AUDIO_DTB_SURGERY_CANDIDATE_20260830.diff`；反编译全文 `out/v9_dtb/v9_audio_candidate.dts`
- 适配树（只读参照）：`out/linux-sdm660-oppor11-t-qcom-sdm660-7.0.y/`（Linux 7.0.14 系，下称"树"）

---

## 0. 头版结论（与任务前提的出入，必须先看）

任务前提假设"现行手术 DTB 的 DSP 链是下游绑定（qcom,msm-audio-apr / qcom,pil-tz-generic / qcom,msm-i2c-v2 等）"。**实地反编译证伪**：

- `dtb_v9.dtb` 内 **无任何下游音频绑定残留**（`qcom,msm-audio-apr`、`qcom,q6core-audio`、`qcom,glink`(下游式)、`qcom,pil-tz-generic`、`qcom,msm-i2c-v2` 全部 0 命中）。
- apr/glink/q6 链 **已是标准 mainline 形态**，且与树内参照 `arch/arm64/boot/dts/qcom/sdm660-oppo-r11t.dts`（+ `sdm630.dtsi`、`sdm660-xiaomi-jasmine.dts`）逐节点同构。
- adsp 已是 `qcom,q6v5-pas` 系（`qcom,sdm660-adsp-pas`），codec i2c 总线已是 `qcom,i2c-qup-v2.2.1`（I2C_QUP=y，驱动内建）。

**真实卡点（主机侧可证的两条）**：

| # | 卡点 | 证据 | 候选件处置 |
|---|---|---|---|
| A | adsp 固件名与部署路径不匹配：DTB `firmware-name = "adsp.mdt"`，但固件盘点部署集放在 `/lib/firmware/qcom/sdm660/adsp.mdt`（`INVENTORY.tsv` 全部段同址）。本树 `drivers/soc/qcom/mdt_loader.c` **无** `fw_name_for_request()` 平台子路径逻辑（7.0.y 新 API 未回移），段名按 `fw_name` 前缀直拼（`.mdt`→`.bNN`）→ adsp 必加载失败 → glink/apr 永不就绪 → q6 组件永不注册 → 声卡 **永久 EPROBE_DEFER**。这正是"声卡预期不注册"的最可能主因 | `drivers/remoteproc/qcom_q6v5_pas.c` L753-757（DT firmware-name 覆盖）；`drivers/soc/qcom/mdt_loader.c` L79-84（段名=原名换后缀）；`backups/firmware_inventory_r11s_20260830_043151/INVENTORY.tsv` | 改为 `"qcom/sdm660/adsp.mdt"`（DTB-only 修复，语义自洽） |
| B | `pinctrl@15070000`（lpass-lpi-pinctrl）缺 `#pinctrl-cells`。注：运行时声卡 pinctrl-0 按裸 phandle 解析（`drivers/pinctrl/devicetree.c` `pinctrl_dt_to_map` 不用 cells），**不阻塞声卡注册**；但为绑定强制项且后续 gpio 消费者必需 | `Documentation/devicetree/bindings/pinctrl/pinctrl.yaml`（#pinctrl-cells）；`qcom,lpass-lpi-common.yaml`（$ref pinctrl.yaml） | 补 `#pinctrl-cells = <1>` |

**任务文案两处与证据不符，更正如下**：
1. "max98927L @ 0x3a" —— 原厂 17011 dtsi（`recon/third_party_r11s_source_evidence_20260730_051654/color597_kernel_17011/sdm660-mtp.dtsi` L532-550）与现行 DTB 均为 **tfa9890 @ 0x36**（`nxp,tfa98xx`→`nxp,tfa9890`），与树内参照 `sdm660-oppo-r11t.dts` 一致。DTB 保持 `nxp,tfa9890@0x36` 不动（驱动 `tfa989x.c` 支持，SND_SOC_TFA989X=m）。
2. "Sam 的 glue 机器驱动"（`sound/soc/qcom/sdm660-oppo-r11s.c`）**未编入现行 .config**（`CONFIG_SND_SOC_SDM660_OPPO_R11S` 未设；`CONFIG_SND_SOC_MAX98927 is not set`）。现行 DTB 声卡 compatible `qcom,sdm660-internal-sndcard` 对应的是树内 `sound/soc/qcom/sdm660-internal.c`（`CONFIG_SND_SOC_SDM660_INT=m`），且该驱动 of_match 要求根节点含 `qcom,sdm660`（DTB 已满足）。另：glue 驱动按 `maxim,max98927`/`maxim,max98927L` 找扬声器，**不含 `nxp,tfa9890`**——即使启用也会永远 defer（源码缺口，非本次可改）。

---

## 1. 音频相关节点登记（dtb_v9.dtb 实地反编译）

引用记法：`0xNN`=phandle；"提供者"列标注该引用指向的节点/驱动。

### 1.1 DSP/远端链

| 节点 | compatible / 关键属性 | 引用（时钟/电源/内存） | mainline 有效性 |
|---|---|---|---|
| `remoteproc@15700000`（adsp） | `qcom,sdm660-adsp-pas`；`firmware-name="adsp.mdt"`（候选件改 `qcom/sdm660/adsp.mdt`） | clocks=`<0x26 0x00>`(rpmcc XO ✓)；power-domains=`<0x32 0x00>`(rpmpd CX ✓)；memory-region=`0x92`(reserved adsp@92a00000, 32MB ✓)；qcom,smem-states=`0x93`(smp2p-adsp ✓)；interrupts-extended 含 GIC+`0x91`(smp2p slave-kernel ✓) | ✅ `bindings/remoteproc/qcom,adsp.yaml` 枚举含 `qcom,sdm660-adsp-pas`；`CONFIG_QCOM_Q6V5_PAS=m`。**唯一实雷=固件路径（卡点 A）** |
| ↳ `glink-edge` | label="lpass"；mboxes=`<0x1a 0x09>`(apcs mbox ✓)；qcom,remote-pid=2 | — | ✅ pas 驱动自建，无需 compatible |
| ↳↳ `apr` | `qcom,apr-v2`；`qcom,glink-channels="apr_audio_svc"`；`qcom,domain=4`(ADSP)；#addr/size-cells=1/0 | — | ✅ `bindings/soc/qcom/qcom,apr.yaml` 全部满足（required: compatible+qcom,domain）；`CONFIG_QCOM_APR=m` |
| ↳↳↳ `service@3` | `qcom,q6core` | — | ✅ `bindings/sound/qcom,q6core.yaml` |
| ↳↳↳ `service@4` | `qcom,q6afe` | — | ✅ `bindings/sound/qcom,q6afe.yaml` |
| ↳↳↳↳ `clock-controller` | `qcom,q6afe-clocks`；#clock-cells=2（ph 0x90） | — | ✅ `bindings/sound/qcom,q6dsp-lpass-clocks.yaml`；`CONFIG_SND_SOC_QDSP6_AFE_CLOCKS=m` |
| ↳↳↳↳ `dais` | `qcom,q6afe-dais`（ph 0xa0）；dai@16(PRI_MI2S_RX,sd0)/dai@18(SEC_MI2S_RX,sd0)/dai@81(INT0_MI2S_RX,sd01)/dai@88(INT3_MI2S_TX,sd01) | — | ✅ `qcom,q6dsp-lpass-ports.yaml`；DAI ID 与 `include/dt-bindings/sound/qcom,q6dsp-lpass-ports.h` 一致（16/18/0x89/0x90） |
| ↳↳↳ `service@7` | `qcom,q6asm`；`dais`=`qcom,q6asm-dais`(ph 0x9f) dai@0/@1（MM1/MM2）；`iommus=<0x94 0x01>`（apps smmu `qcom,sdm630-smmu-v2` ✓） | — | ✅ `bindings/sound/qcom,q6asm.yaml`+`qcom,q6asm-dais.yaml` |
| ↳↳↳ `service@8` | `qcom,q6adm`；`routing`=`qcom,q6adm-routing`(ph 0xa1) | — | ✅ `qcom,q6adm.yaml`+`qcom,q6adm-routing.yaml` |
| ↳↳ `fastrpc` | `qcom,fastrpc` + compute-cb@1..4（iommus 0x94） | — | ✅（非音频必需，保留不动） |
| `smp2p-adsp` | `qcom,smp2p`；remote-pid=2 | — | ✅ |
| `reserved-memory: adsp@92a00000`（ph 0x92） | 32MB no-map | — | ✅ 与 pas 绑定匹配 |
| `reserved-memory: adsp-region@f6000000` | 8MB no-map，**无 phandle、无人引用** | — | ⚠️ 历史残留（下游 ADSP heap 风格），保留不动（删除非必需，且有 no-map 无害） |
| `remoteproc`（rpm-proc）→`glink-edge`(`qcom,glink-rpm`)→`rpm-requests` | rpmcc(`qcom,rpmcc-sdm660`,ph 0x26)/rpmpd(`qcom,sdm660-rpmpd`,ph 0x32) | — | ✅ 音频时钟/电源的提供者本体 |

### 1.2 codec 与总线

| 节点 | compatible / 关键属性 | 引用 | mainline 有效性 |
|---|---|---|---|
| `audio-codec@152c0000`（LPASS 数字 codec） | `qcom,msm8916-wcd-digital-codec`；clock-names="ahbix-clk,mclk" | clocks=`<0x8f>`（fixed-clock int-cdc-bclk 1.536MHz ✓）+`<0x90 0x33 0x01>`（q6afe-clocks mclk，9.6MHz assigned-rate ✓） | ✅ `bindings/sound/qcom,msm8916-wcd-digital-codec.yaml`（clock-names 常量一致）；`CONFIG_SND_SOC_MSM8916_WCD_DIGITAL=m` |
| `pmic@3/audio-codec@f000`（SPMI 模拟 codec） | `qcom,pm8916-wcd-analog-codec`（ph 0xa4）；mbhc/micbias 属性组 | vdd-*-supply=`0x20`（pm660l S2? 见节点内）；qcom,micbias-lvl 等树内驱动支持 | ✅ `bindings/sound/qcom,pm8916-wcd-analog-codec.yaml`；`CONFIG_SND_SOC_MSM8916_WCD_ANALOG=m` |
| `i2c@c1b6000`（BLSP QUP，codec 总线） | `qcom,i2c-qup-v2.2.1`；400kHz；status=okay | clocks=`<0x25 0x25/0x24>`（gcc ✓）；dmas=`0x7a`（bam ✓）；pinctrl 0x81/0x82（tlmm ✓） | ✅ `drivers/i2c/busses/i2c-qup.c` of_match 含该名；`CONFIG_I2C_QUP=y`（内建）。**无需迁移，无下游 `qcom,msm-i2c-v2` 残留** |
| ↳ `audio-codec@10`（耳机 DAC） | `asahi-kasei,ak4376`（ph 0xa2）；pdn-gpios=tlmm76；avdd/tvdd=`0x50`(pm660 L8 ✓) | — | ✅ 树内 `sound/soc/codecs/ak4375.c` of_match 含 `asahi-kasei,ak4376`（Sam 补丁亦加了下游别名）；`CONFIG_SND_SOC_AK4375=m`；原厂 gpio76/电源与 17011 dtsi 一致 |
| ↳ `audio-codec@36`（扬声器 PA） | `nxp,tfa9890`（ph 0xa3）；reset-gpios=tlmm80；vddd=`0x80`(pm660 L13 ✓) | — | ✅ `sound/soc/codecs/tfa989x.c`；`CONFIG_SND_SOC_TFA989X=m`。与原厂 17011 `tfa98xx@36` 及树内 `sdm660-oppo-r11t.dts` 一致 |
| `pinctrl@15070000` | `qcom,sdm660-lpass-lpi-pinctrl`（ph 0x8e）；gpio-controller；#gpio-cells=2；**缺 #pinctrl-cells（候选件补）** | 无时钟/电源引用（驱动 `pinctrl-lpass-lpi.c` 用 `devm_clk_bulk_get_optional`，可空） | ✅ 驱动 `drivers/pinctrl/qcom/pinctrl-sdm660-lpass-lpi.c`；`CONFIG_PINCTRL_SDM660_LPASS_LPI=m` |
| tlmm 状态 `r11t-pri-mi2s-active-state`(0x9d)/`r11t-sec-mi2s-active-state`(0x9e) | function pri_mi2s/sec_mi2s | — | ✅ |

### 1.3 声卡（/sound）

- compatible=`qcom,sdm660-internal-sndcard`，model="OPPO R11T" → 驱动 `sdm660-internal.c`（L461 of_match 同名；L165 检查根 `qcom,sdm660` ✓）。
- pinctrl-0=`<0x9b 0x9c 0x9d 0x9e>`（lpi cdc-pdm/dmic + tlmm pri/sec mi2s，跨控制器引用合法；按裸 phandle 解析，见卡点 B）。
- audio-routing 34 项：机器件 "Headphone Jack"/"Mic Jack"/"Speaker" 由驱动自带 dapm widgets 提供（`sdm660-internal.c` L418-422），codec 端 "OUT"=tfa989x 输出、"HPH_L/R/HPL/HPR"=wcd-analog、"Digital *"=wcd-digital 前缀（sound-name-prefix="Digital" ✓）。
- 6 条 dai-link：mm1/mm2(q6asm FE)、pri-mi2s→ak4376、sec-mi2s→tfa9890、int0-mi2s→(pm660l_codec,wcd-digital)、int3-mi2s(capture)。phandle 0x9f/0xa0/0xa1/0xa2/0xa3/0xa4/0xa5 全部存在且指向 1.1/1.2 中节点。**与树内 `sdm660-oppo-r11t.dts` 的 &sound 逐链同构**。

### 1.4 时钟/电源引用兼容性结论

全部音频时钟/电源引用指向 **mainline 提供者**：rpmcc-sdm660（XO）、rpmpd（CX）、gcc-sdm660（i2c/smmu 总线时钟）、fixed-clock（int-cdc-bclk）、q6afe-clocks（mclk）。**无任何引用指向下游专用 clock-controller** → **时钟引用无阻塞项**（与任务预案中"可能整体阻塞"的担心不符，如实记录）。

---

## 2. 节点级手术 diff（全部改动，共 2 行）

完整留档：`recon/AUDIO_DTB_SURGERY_CANDIDATE_20260830.diff`。

```diff
@@ pinctrl@15070000 @@
 			#gpio-cells = <0x02>;
+			#pinctrl-cells = <0x01>;
 			gpio-ranges = <0x8e 0x00 0x00 0x20>;

@@ remoteproc@15700000 @@
-			firmware-name = "adsp.mdt";
+			firmware-name = "qcom/sdm660/adsp.mdt";
```

| 改动 | 依据（绑定/源码路径，均在适配树内） |
|---|---|
| 补 `#pinctrl-cells = <1>` | `Documentation/devicetree/bindings/pinctrl/pinctrl.yaml`（pinctrl 控制器强制项）；`qcom,lpass-lpi-common.yaml` allOf $ref pinctrl.yaml；运行时为后续 gpio 消费者必需（声卡本身按裸 phandle 解析，不受影响） |
| `firmware-name` 加 `qcom/sdm660/` 前缀 | 部署集 `INVENTORY.tsv`（`/lib/firmware/qcom/sdm660/adsp.{mdt,b00..b21}`）；`drivers/soc/qcom/mdt_loader.c`（段名=原名换后缀，无平台前缀逻辑）；`drivers/remoteproc/qcom_q6v5_pas.c`（DT firmware-name 直接透传）。候选写法与 linux-firmware 主流布局（`qcom/<soc>/`）一致 |

**未动清单（字节级）**：显示（mdss/dsi/panel@1 ams596w401、sofeg01_s）、触摸（rmi4@20 及其 pinctrl/电源）、电池/充电（battery@4000、pm660_charger、fuel-gauge）、无线（wcn3990 wifi/bt、mpss remoteproc、ipa）、USB、eMMC。验证方法：候选 dtb 反编译回文本与原件文本 `diff -u`，**全部差异仅上述 2 行**；抽检 20 个关键 phandle（0x8e/0x8f/0x90-0x94/0x9f-0xa5/0x25/0x26/0x28/0x1a/0x32）数量逐一相同。

**无需注入/改写 apr/glink/q6/pil 链**：现状即 mainline（§0），注入只会引入回归风险。

---

## 3. 阻塞项与缺口清单（按可处置性）

| # | 项 | 性质 | 处置 |
|---|---|---|---|
| 1 | adsp 固件路径不匹配（卡点 A） | DTB 可修 | **候选件已修**。备选方案（若不想动 DTB）：rootfs 内做 `/lib/firmware/adsp.{mdt,b*}` → `qcom/sdm660/` 符号链接——两者取一，勿重复 |
| 2 | glue 驱动 `sdm660-oppo-r11s.c` 未编入（`CONFIG_SND_SOC_SDM660_OPPO_R11S` 未设、`CONFIG_SND_SOC_MAX98927 is not set`） | 源码/config 侧，**本轮不可改**（只读约束） | 记录：现行路线实际机器驱动是 `sdm660-internal.c`（已编入，compatible 匹配）。glue 是否启用由后续编译轮定；若启用须同时补 `nxp,tfa9890` 扬声器匹配（现只认 maxim,max98927/L，会永远 defer） |
| 3 | cdsp 节点无 firmware-name → 默认 "cdsp.mdt"，同样与 `qcom/sdm660/cdsp.mdt` 部署位不匹配 | 非音频链，未动 | 记录；若后续启用 cdsp 同样加前缀或做符号链接 |
| 4 | 音频模块自动加载依赖 rootfs（全部为 =m：sdm660-int/qdsp6/ak4375/tfa989x/wcd*/lpi-pinctrl/q6v5-pas/apr） | 上板验证项 | 验收脚本（§6）检查 /proc/asound/cards 与 dmesg defer 行；若 Alpine rootfs 无模块自拉起，需 modprobe 或补 mdev/udev 规则（后续轮） |
| 5 | 任务文案 "max98927L@0x3a" 与证据（tfa9890@0x36）冲突 | 记录更正 | 不硬造 max98927 节点（无板级证据，硬加会使 tfa 总线冲突/误探测） |

---

## 4. 风险评估

**结论：音频链失败不影响其他子系统；候选件不引入新的启动风险。** 论证：

1. 改动 1（#pinctrl-cells）只新增属性，不删不改任何现有值；该节点未被其他子系统以 pinctrl phandle 方式消费（声卡按裸 phandle 解析，见 §0 源码分析），行为只会更宽松。
2. 改动 2 只改一个字符串。若固件仍加载失败，行为与现状完全相同（adsp probe 报错→glink 不就绪→apr/q6 不注册→声卡 defer），**不会 panic、不波及显示/触摸/电池/无线**（它们不依赖 adsp）。
3. apr/q6/声卡全部是 **probe-defer 式失败**（EPROBE_DEFER 循环），无强制超时、无 oops 路径；q6v5-pas 固件加载失败仅 `dev_err` + probe 失败。
4. 未动字节覆盖显示/触摸/电池/无线/USB/eMMC 全部节点（diff 证据 §2）。
5. 隔离手段（若需）：候选件是独立文件，回滚 = 继续刷原 `dtb_v9.dtb`；进一步隔离可临时把 /sound 节点 status 置 disabled（本轮未做，因无必要）。
6. 残余风险（上板可能失败点，均限于音频内）：adsp 需 SCM/TZ 放行（`qcom_scm_is_available()` defer、smem/smp2p 初始化时序）；ak4376 PDN/tfa9890 reset GPIO 若被原厂固件占用可能 probe 失败 → 仅该 codec 链失败，声卡其余部分仍注册。

## 5. 候选件指纹

```
文件：out/v9_dtb/dtb_v9_audio_candidate.dtb
大小：64,564 B（原件 64,521 B，+43 B = 1 属性 + 字符串加长）
sha256：1f2ac6749270c2677a988ad5197b8181ef95fa615e9bc0700f39720ee754bb00
原件：out/v9_dtb/dtb_v9.dtb  sha256 b6fce4bbb9639123cb3287af39d82843bcdcc3e9be72e30208da0fbe1a08dae7（未动）
```

## 6. 采用条件（并入正式镜像前必须通过的验证）

1. `tools/r11s_onboard_check.sh` 音频段：`/proc/asound/cards` 出现 "OPPO R11T"（或 sdm660-internal 卡）。
2. dmesg 验证顺序：`qcom_q6v5_pas … firmware qcom/sdm660/adsp.mdt` 加载成功 → `remoteproc: adsp is up`（glink 就绪）→ apr/q6afe/q6asm 注册 → 声卡注册；无 "audio components not described" / 永久 defer。
3. 固件文件实际在位于 `/lib/firmware/qcom/sdm660/`（rootfs 侧抽查 `ls`）。
4. 触摸/显示/电池/无线段判定不因换用候选件而回退（对照同一轮 dtb_v9 基线上板记录）。
5. 若第 1 条失败但其余全绿 → 判定为音频链内部问题，回滚仅音频意义（换回原件即可），不影响采用其它子系统修复。

---
*附：反编译原文 `out/v9_dtb/v9_audio_candidate.dts`；v8→v9 对比显示 v8 已含同一 mainline 音频链（音频手术早于本任务完成，本轮仅补 2 行）。*
