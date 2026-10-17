# DOMAIN_build — 构建 / 打包 / 验证覆盖域

> Wave 2 · 子代理只读取证 · 2026-09-02 · 完整证据链见 `LEDGER_v14_20260902.md` F08、F14-F16
> **注**：本域子代理输出被截断（丢失后半段），后半部分（合成步骤 / 门禁 / 验证清单 / 回滚链）**由 Hub 依据已有上下文补齐并实测核验**，已写入 `R11S_V14_IMAGE_PLAYBOOK_20260902.md`。

## 结论（子代理已确认部分）

1. **`CONFIG_SND_SOC_SDM660_INT` 两处均为 `=y`**（defconfig:526 / .config:4468），音频基础通路已开；但 **R11s 专用 machine driver `CONFIG_SND_SOC_SDM660_OPPO_R11S` 在 defconfig 中完全缺失、在 .config:4469 显式 `is not set`**，而驱动源码 `sdm660-oppo-r11s.c` 确实存在 → 该驱动不会编译进 v14，声卡 probe 是 v14 最高风险缺口。
2. 抽查的其余关键项（面板 `SOFEG01_S` / `AMS596W401`、`DRM_MSM`、RMI4 三件套、`ATH10K_SNOC`）defconfig 与 .config **取值全部一致，零差异**；GPU 走 `DRM_MSM` 主线路径，两边均无 KGSL。
3. `r11s_bootimg_pack.py` **默认 dry-run**（只算不写），`--write` 才落盘；它打印 EXACT COMMAND、三份输入 sha256、Image.gz / kernel.gz-dtb 中间体 sha256、预期 boot.img sha256+size+layout。
4. **脚本 CANON 默认值与 v13 既有事实冲突**：默认 base 0x0 / kernel 0x8000 / ramdisk 0x1000000 / os_version 0，而 v13 实际为 0x80000000 / 0x80008000 / 0x83000000 / 0x12000139 → v14 必须**逐项显式传参**。
5. v14 三份原料**全部有归档 sha256 可核**；且 **v13 的 ramdisk 与 v10 归档的 `ramdisk_v9_orig.cpio` 哈希完全相同**（`1ad74196…`），可交叉印证版本谱系。

## 证据

**音频配置：INT 已开、OPPO_R11S 未开（Wave 1 缺口补齐）**
```
$K/arch/arm64/configs/r11s_defconfig:526
526:CONFIG_SND_SOC_SDM660_INT=y

$R/build/r11s_phase2/.config:4468-4469
4468:CONFIG_SND_SOC_SDM660_INT=y
4469:# CONFIG_SND_SOC_SDM660_OPPO_R11S is not set
```

**defconfig 中不存在任何 R11S/OPPO 音频 machine 符号**（pattern `OPPO|R11S|SDM660` 仅 5 行命中）
```
  1:CONFIG_LOCALVERSION="-sdm660-gcc+"
410:CONFIG_PINCTRL_SDM660=y
414:CONFIG_PINCTRL_SDM660_LPASS_LPI=y
526:CONFIG_SND_SOC_SDM660_INT=y
856:CONFIG_INTERCONNECT_QCOM_SDM660=y
```

**该驱动源码与 Kconfig 符号确实存在**
```
$K/sound/soc/qcom/sdm660-oppo-r11s.c
$K/sound/soc/qcom/Kconfig:182   （config SND_SOC_SDM660_OPPO_R11S）
$K/sound/soc/qcom/Makefile:28,44
```

**面板 / DRM_MSM：两处一致**
```
defconfig:482-495   CONFIG_DRM_MSM=y / #MDP4 not set / #HDMI not set /
                    :494 SOFEG01_S=y / :495 AMS596W401=y
.config:3989-3998   CONFIG_DRM_MSM=y / MDP5=y / DPU=y / DSI=y
.config:4094-4095   SOFEG01_S=y / AMS596W401=y
```

**触摸 RMI4 / 无线：两处一致**（.config 多出的为默认值展开）
```
defconfig:343-347   ATH10K=y / ATH10K_SNOC=y
defconfig:386-388   RMI4_CORE=y / RMI4_I2C=y / RMI4_F1A=y
.config:2252-2256   ATH10K=y / ATH10K_SNOC=y
.config:2507-2516   RMI4_CORE/I2C/F03/F11/F1A =y
```

**打包工具契约：dry-run 与 --write 的语义边界** — `tools/r11s_bootimg_pack.py:22-37`
```
22: SAFETY / GATES (CLAUDE.md):
23:   - Default mode is DRY-RUN: it reads inputs, computes the would-be boot.img
24:     in memory and PRINTS the exact pack command + expected sha256. It writes
25:     NOTHING and never touches a device.
26:   - `--write` produces the boot image on the host (still no device access).
36:     Image.gz is produced deterministically (gzip, mtime=0, level 9) by this
37:     script itself, so dry-run sha256 == `--write` sha256 on the same host.
```

## Hub 补齐部分（实测核验，2026-09-02）

**三份原料 hash（实测）**
```
2135d6cbdeb5c03893e447d95a221a451f4d4d2bcd7b09c27d99e7713db73676  v13/Image.gz      (13,911,094 B)
39aba9aa3d8d562b17836aa777f77390b01f938bbea2df1274c805eaf8fa43e5  v13/dtb_v12.dtb   (64,588 B)
d3fc164ab73c6141edeed011976ecab25ab02a3a693f60ac56c5beac803ce3e1  v10/ramdisk_v10.cpio (1,122,304 B)
```

**谱系实证（B4 定案）**
```
v13/ramdisk_v6.cpio        = 1ad7419650ba1aba6fba030daa014312dd431a44eaf65e1f32f3f0e663e9a7d2
v10/ramdisk_v9_orig.cpio   = 1ad7419650ba1aba6fba030daa014312dd431a44eaf65e1f32f3f0e663e9a7d2
```
→ **v13 用的就是 v9 原始 ramdisk，完全没有切根 init**（哈希实证，非推断）

**验证覆盖缺口（B1）** — 7 个提交标注「验证状态=未上板」
```
ddff10388 audio v11 · d947f542d v9 integrated · 476821c28 rmi4 f12 hardening
a02aced7f rmi4 PDT sanity · b55601e7d rmi4_i2c retry · e520efd19 rmi4_i2c supply
ce07c13f5 SOFEG01_S panel driver · 11bf7be6f rmi4 PDT entries
```

## 产出

- 合成步骤 / 门禁清单 / 回滚链 / 待授权命令 → `R11S_V14_IMAGE_PLAYBOOK_20260902.md`
- 上板验证关键字清单 → `R11S_V14_IMPROVEMENT_PLAN_20260902.md` §六

## 未取证

1. **defconfig 全量一致性未逐项比完**：仅抽查了音频/面板/DRM/触摸/无线五类，其余（如 remoteproc、 interconnect、pinctrl）未比对。
2. **`CONFIG_SND_SOC_SDM660_OPPO_R11S=y` 的连带依赖未推导**（如是否需要额外的 APR/Q6 系列配置项）。
3. **v11/v12 的完整 sha256 未从归档补查**（STATUS.md 中只有前缀 `a07a5ef5…` / `c93e0039…`）。
4. 子代理输出截断部分（脚本参数全表、v14 门禁细节）未由子代理产出，已由 Hub 补齐但**未经子代理独立复核**。
