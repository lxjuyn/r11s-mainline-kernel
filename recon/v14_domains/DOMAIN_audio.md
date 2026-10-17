# DOMAIN_audio — 音频域

> Wave 1 · 子代理只读取证 · 2026-09-02 · 完整证据链见 `LEDGER_v14_20260902.md` F08-F10

## 结论

1. **树内已有 `sdm660-internal.c`，且已挂进 Kconfig/Makefile** —— v14 音频是「上游补丁的本地移植改造版」，不是自写；同时树内另有一个自写的下游兜底驱动 `sdm660-oppo-r11s.c`。
2. **两个 codec 的 compatible 均不含上游新增的 PM660L / SDM660** —— 树内改用下游别名 `qcom,pmic-analog-codec` / `qcom,msm-digital-codec` 兜底，功能等价但未跟随上游。
3. **internal MI2S 在 `sound/soc/qcom/**/*.c` 中零命中** —— 是否具备端口定义未获证实（头文件 `qcom,q6dsp-lpass-ports.h` 确实被 `sdm630.dtsi` 引用）。
4. **v12 实刷 DTB 的 `sound` 节点属性齐全**（model / audio-routing / dai-link 均有，152c0000 = okay）→ `sdm660-int-sndcard` defer 不像 DTB 属性缺失，更可能来自内核侧。
5. **`152c000.audio-codec` = LPASS 内建 WCD 数字 codec `@0x152c0000`**，其 clocks 依赖 `q6afecc`（ADSP APR 服务），defer 指向 ADSP 未启动链。

> **补充（Wave 2 构建域交叉发现，本域未查）**：`CONFIG_SND_SOC_SDM660_OPPO_R11S` 在 `.config:4469` 显式 `is not set`、defconfig 中完全缺失，而源码存在 → **A1，v14 最高风险缺口**。`CONFIG_SND_SOC_SDM660_INT` 两处均 `=y`（`r11s_defconfig:526` / `.config:4468`）。

## 证据

**机器驱动已存在并已接入构建**
```
$K/sound/soc/qcom/sdm660-internal.c   （12.28 KB，非上游 271 行原始版）
  167:	     of_machine_is_compatible("qcom,sdm660"))) {
  160:	SDM630/SDM636/SDM660 ADSP firmware has a buffer size limit of ~256KB.
  460:static const struct of_device_id snd_sdm660_int_device_id[] = {
  461:	{ .compatible = "qcom,sdm660-internal-sndcard", },
  470:		.name = "sdm660-int-sndcard",
$K/sound/soc/qcom/Kconfig
  170:config SND_SOC_SDM660_INT
  182:config SND_SOC_SDM660_OPPO_R11S
$K/sound/soc/qcom/Makefile
   27:snd-soc-sdm660-int-y := sdm660-internal.o
   28:snd-soc-sdm660-oppo-r11s-y := sdm660-oppo-r11s.o
   43:obj-$(CONFIG_SND_SOC_SDM660_INT) += snd-soc-sdm660-int.o
   44:obj-$(CONFIG_SND_SOC_SDM660_OPPO_R11S) += snd-soc-sdm660-oppo-r11s.o
```

**analog codec of_match：有 pm8916 + 下游别名，无 PM660L** — `sound/soc/codecs/msm8916-wcd-analog.c:1407-1418`
```c
1408:	{ .compatible = "qcom,pm8916-wcd-analog-codec", },
1410:	 * R11s mainline port: the OPPO R11s downstream DTB declares the
1411:	 * PM660L internal analog codec as "qcom,pmic-analog-codec"
1417:	{ .compatible = "qcom,pmic-analog-codec", },
```

**digital codec of_match：有 msm8916 + 下游别名，无 SDM660** — `msm8916-wcd-digital.c:1230-1239`
```c
1230:	{ .compatible = "qcom,msm8916-wcd-digital-codec" },
1232:	 * R11s mainline port: ... LPASS internal digital codec (@0x152c0000) as
1233:	 * "qcom,msm-digital-codec"; it is the same msm8916-wcd digital codec IP
1239:	{ .compatible = "qcom,msm-digital-codec" },
```

**internal MI2S 零命中**
```
pattern: internal.?mi2s|int_mi2s|INTERNAL_MI2S
path: $K/sound/soc/qcom (glob *.c)   →  Found 0 matching results
间接证据（头文件存在并被 SoC dtsi 引用）：
$K/arch/arm64/boot/dts/qcom/.sdm660-oppo-r11s.dtb.dts.tmp:52
  # 1 ".../dt-bindings/sound/qcom,q6dsp-lpass-ports.h" 1
```

**v12 实刷 DTB 音频节点** — `dtb_v12.verify.dts`
```
 1942: audio-codec@f000 { compatible = "qcom,pm8916-wcd-analog-codec"; ... status = "okay"; }
 2899: audio-codec@152c0000 { compatible = "qcom,msm8916-wcd-digital-codec";
 2901:   reg = <0x152c0000 0x400>;  2908: status = "okay";  2909: phandle = <0xa5>; }
 2945: compatible = "qcom,q6afe";  2956: compatible = "qcom,q6afe-dais";
 3012: routing { (q6adm-routing) }  3254: sound { compatible = "qcom,sdm660-internal-sndcard";
 3256:   model = "OPPO R11T";
 3259:   audio-routing = "RX_BIAS\0Digital MCLK\0 ... AMIC2\0MIC BIAS External2";
 3261:   mm1-dai-link { sound-dai = <0x9f 0x00>; }   (0x9f = q6asm-dais)
 3281:     sound-dai = <0xa0 0x10>;   (0xa0 = q6afedai)
 3321:     codec { sound-dai = <0xa4 0x00 0xa5 0x00>; }
```
→ 必需属性齐备；未见 `pinctrl-names` / `pinctrl-0`（MI2S/LPI 复用）。另有 `:2821 compatible = "qcom,sdm660-lpass-lpi-pinctrl"` 存在但未确认被引用。

**树内 SoC dtsi 的默认状态** — `.sdm660-oppo-r11s.dtb.dts.tmp`
```
 2431:  lpass_codec: audio-codec@152c0000 {
 2435:   clocks = <&int_cdc_bclk>, <&q6afecc 51 0x1>;
 2439:   assigned-clocks = <&q6afecc 51 0x1>;  2440: assigned-clock-rates = <9600000>;
 2445:   status = "disabled";            <-- 树内默认关
 2495:   q6afecc: clock-controller { compatible = "qcom,q6afe-clocks"; };
 2500:   q6afedai: dais { compatible = "qcom,q6afe-dais"; };
 2684:  sound: sound { };               <-- SoC 层空节点，需板级填充
```
defer 链：`lpass_codec` → `&q6afecc`（q6afe 时钟）→ ADSP remoteproc/APR 就绪。

## 补丁级定位

| 项 | 位置 | 改法 | 收益 | 风险 |
|---|---|---|---|---|
| **A-4（最高优先）** | `.config:4469` + `r11s_defconfig` | `CONFIG_SND_SOC_SDM660_OPPO_R11S=y`，改完 `savedefconfig` 回写 | R11s 专用 machine driver 进入内核 | 低；但**实施前需先确认其 of_match 是否与 `sdm660-internal.c` 冲突** |
| B | 板级 DTS（覆盖 `.tmp:2445`） | `&lpass_codec { status = "okay"; }` | 消除 152c000 被禁用（若 v14 用树内 DTB） | 低 |
| C | 板级 DTS（`.tmp:2684` 空 sound 节点） | 补 model / audio-routing / dai-link（可照抄 v12 DTB `:3254-3339`） | 声卡可注册 | 低；属性写错仅无声 |
| D | `q6afe-dai.c`、`q6dsp-lpass-ports.c` | 若确无 internal MI2S：按上游 v4 补 AFE port（与 DTB 中 `0x10/0x12/0x89/0x90` 对表） | 内部 MI2S 通路打通 | **中高**：port id/路由错 = 无声、破音、串道；不变砖 |
| F | DTB 的 MI2S pinctrl | 若走 LPI/MI2S 引脚，补 `pinctrl-names` + `pinctrl-0/1` | 消除引脚复用缺失导致的静音 | 中：复用错 = 无声 |

**建议不改（A5）**：codec compatible 保持下游别名，以维持与 v12/v13 DTB 的双向兼容。

## 未取证

- **`$K/arch/arm64/boot/dts/qcom/sdm660.dtsi` 是否存在未证实**：对该路径 grep `152c000|audio-codec|lpass|sound|q6afe|wcd` 返回 0 命中；预处理产物显示 SoC dtsi 实为 **`sdm630.dtsi`**。音频节点定义位置需逐个打开验证。
- **q6dsp internal MI2S 是否就绪未证实**：grep 0 命中，但未单独打开 `q6afe-dai.c` / `q6dsp-lpass-ports.c` 看实际命名（上游可能用其他写法）。
- **`CONFIG_SND_SOC_SDM660_INT` 是否 =y**：本域未查（超出起始路径），由 Wave 2 构建域补齐 → 结论为 **=y**。
- 上游 v1/v4 补丁是否已合入主线未证实（本轮未做联网核实）。
- `dtb_v12.verify.dts` 中 `pinctrl-names/0` 未出现在检索片段，不能断言一定缺失。

## 与既有事实的冲突

1. **「DTB 属性缺失导致声卡 defer」vs 证据**：v12 DTB 中 `audio-codec@152c0000` = `status="okay"`、`sound` 节点齐全 → **defer 更可能来自内核侧**（CONFIG 未开 / ADSP-q6afe 时钟域未就绪），而非 DTB 缺口。
2. **「上游补丁未证实合入」vs 树内已存在同名驱动**：`sdm660-internal.c` 12.28KB、含 SDM660 ADSP 256KB 缓冲特判，与上游 v1 的 271 行体量不符 → 是本地移植改造版，**"移植"与"上游合入"必须区分表述**。
3. **社区「SDM660 Audio = Partial」vs 本地 DTB 完整性**：v12 DTB 音频拓扑已相当完整，短板更可能在内核侧使能，而非设备树描述能力。
