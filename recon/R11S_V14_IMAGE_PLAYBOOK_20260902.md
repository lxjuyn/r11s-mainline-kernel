# R11s v14 镜像合成与刷写预案

> 生成：2026-09-02 · **本文件只到"待授权"为止，不含任何已执行的触设备动作**
> 前置：先读 `R11S_V14_IMPROVEMENT_PLAN_20260902.md`（决定 v14 包含哪些代码改动）
> 依据：`CLAUDE.md §3`（触设备动作须展示命令 + 目标分区 + 回滚路径 + 风险，取得当次明确确认）

---

## 一、v14 的定义

**v14 = v13 的内核与 DTB（逐字节复用）+ v10 的切根 ramdisk + 追加 `deferred_probe_timeout=30`**

| 项 | 来源 | 说明 |
|---|---|---|
| kernel (Image.gz) | v13 归档 | 含 v12 评审修复 + v13 面板诊断 |
| DTB | v13 归档 `dtb_v12.dtb` | panel@0 okay / panel@1 disabled |
| ramdisk | v10 归档 `ramdisk_v10.cpio` | 支持 `root=/dev/mmcblk1p69` 切根，失败落回救援 shell |
| cmdline | v10 语义 + 追加 | 见下 |

### 三份原料（**已逐项 sha256 核验，2026-09-02**）

| 原料 | 路径 | 大小 | sha256 |
|---|---|---|---|
| Image.gz | `backups/products/products_r11s_phase3_regdiag_v13_20260831_0211/Image.gz` | 13,911,094 B | `2135d6cbdeb5c03893e447d95a221a451f4d4d2bcd7b09c27d99e7713db73676` |
| dtb_v12.dtb | `backups/products/products_r11s_phase3_regdiag_v13_20260831_0211/dtb_v12.dtb` | 64,588 B | `39aba9aa3d8d562b17836aa777f77390b01f938bbea2df1274c805eaf8fa43e5` |
| ramdisk_v10.cpio | `backups/products/products_r11s_phase4_rootfs_v10_20260830_044715/ramdisk_v10.cpio` | 1,122,304 B | `d3fc164ab73c6141edeed011976ecab25ab02a3a693f60ac56c5beac803ce3e1` |

### ⚠ 本轮实证的谱系事实（B4）

```
v13 归档/ramdisk_v6.cpio      = 1ad7419650ba1aba6fba030daa014312dd431a44eaf65e1f32f3f0e663e9a7d2
v10 归档/ramdisk_v9_orig.cpio = 1ad7419650ba1aba6fba030daa014312dd431a44eaf65e1f32f3f0e663e9a7d2
```
→ **v13 用的就是 v9 的原始 ramdisk，完全没有切根 init**。这是 v14 存在的根本理由，已由哈希实证（非推断）。
→ 合成时必须显式指定 `ramdisk_v10.cpio`，**不可**沿用 v13 归档里的 `ramdisk_v6.cpio`。

---

## 二、合成步骤（主机侧，不碰设备）

### 步骤 0：备份
```bash
mkdir -p /home/<user>/claude/r11/backups/source/v14_synth_$(date +%Y%m%d_%H%M)
# 备份将要修改的源码文件（若本轮采纳了 v14a/v14b 的代码改动，按 CLAUDE.md §3 执行）
```

### 步骤 1：逐项显式传参（**关键**，见改进方案 A-9）
`tools/r11s_bootimg_pack.py` 的 CANON 默认值与 v13 既有事实**冲突**，必须显式传：

| 参数 | 必须传的值 | 脚本默认值（**不可用**） |
|---|---|---|
| `--base` | `0x80000000` | `0x0` |
| `--kernel-offset` | `0x8000`（→ 0x80008000） | `0x8000` |
| `--ramdisk-offset` | `0x3000000` | `0x1000000` |
| `--tags-offset` | `0x100`（→ 0x80000100） | — |
| `--pagesize` | `0x1000` | — |
| `--os-version` | `0x12000139` | `0` |
| `--header-version` | `1` | — |

### 步骤 2：dry-run（**先看不写**）
```bash
cd /home/<user>/claude/r11
python3 tools/r11s_bootimg_pack.py \
  --kernel backups/products/products_r11s_phase3_regdiag_v13_20260831_0211/Image.gz \
  --dtb    backups/products/products_r11s_phase3_regdiag_v13_20260831_0211/dtb_v12.dtb \
  --ramdisk backups/products/products_r11s_phase4_rootfs_v10_20260830_044715/ramdisk_v10.cpio \
  --out    out/boot_r11s_v14.img \
  --base 0x80000000 --kernel-offset 0x8000 --ramdisk-offset 0x3000000 \
  --tags-offset 0x100 --pagesize 0x1000 --os-version 0x12000139 --header-version 1 \
  --cmdline 'console=tty0 console=ttyGS0,115200n8 loglevel=7 rootwait rw log_buf_len=1M root=/dev/mmcblk1p69 deferred_probe_timeout=30'
```
dry-run 会打印：EXACT COMMAND、三份输入 sha256、中间体 sha256、预期 boot.img 的 sha256 + size + layout。
**必须先核对三份输入 sha256 与本文第一节一致**，不一致说明取错文件。

### 步骤 3：`--write` 落盘
确认 dry-run 输出无误后，同样命令加 `--write`。

### 步骤 4：门禁校验（**全部通过才可进入刷写请示**）

```bash
# G1 解压后 Image 大小门禁（ABL 硬门槛 0x3180000，安全线取 0x3000000 = 50,331,648 B）
gzip -dc backups/products/products_r11s_phase3_regdiag_v13_20260831_0211/Image.gz | wc -c
# 期望 39,174,656 B → PASS（v13 已验证，v14 内核未变则必然仍 PASS）

# G2 dry-run 预测 hash 与实际产出一致（脚本保证 Image.gz 确定性 gzip mtime=0 level=9）
sha256sum out/boot_r11s_v14.img     # 应与 dry-run 打印的预期值逐字符相同

# G3 header 逐字段对比 v13（唯一允许差异：kernel/ramdisk size + cmdline）
python3 - <<'EOF'
# 对比 out/boot_r11s_v14.img 与 out/boot_r11s_phase3_regdiag_v13.img 的 header
# 关注 base/kernel_addr/ramdisk_addr/tags_addr/pagesize/os_version/header_version
EOF

# G4 DTB 可反编译回读
dtc -I dtb -O dts -o /tmp/v14_dtb_check.dts \
    backups/products/products_r11s_phase3_regdiag_v13_20260831_0211/dtb_v12.dtb
grep -n 'panel@0\|panel@1\|status' /tmp/v14_dtb_check.dts | head -20
# 期望：panel@0 无 status（=okay）、panel@1 status = "disabled"

# G5 ramdisk 内 /init 存在且可执行，且为 v10 语义
mkdir -p /tmp/v14_initrd && cd /tmp/v14_initrd && \
  cpio -idm < /home/<user>/claude/r11/backups/products/products_r11s_phase4_rootfs_v10_20260830_044715/ramdisk_v10.cpio
ls -l /tmp/v14_initrd/init && grep -c 'mmcblk1p69' /tmp/v14_initrd/init
# 期望：/init 存在且 -rwxr-xr-x；mmcblk1p69 出现次数 >0（证明是 v10 切根语义）

# G6 总大小远低于 boot 分区 64MiB
stat -c%s out/boot_r11s_v14.img     # 期望 ~15.1 MB 量级
```

### 步骤 5：归档
```bash
mkdir -p backups/products/products_r11s_v14_<YYYYMMDD_HHMM>/
# 内含：boot_r11s_v14.img、Image.gz、dtb_v12.dtb、ramdisk_v10.cpio、config、
#       README（含合成参数与门禁结果）、SHA256SUMS
```

---

## 三、回滚链（**刷写前必须逐项确认在位**）

| 序 | 镜像 | 路径 | 大小 | sha256 |
|---|---|---|---|---|
| 1 | **v14（新）** | `out/boot_r11s_v14.img` | 待定 | 待定（dry-run 后填） |
| 2 | v13 | `out/boot_r11s_phase3_regdiag_v13.img` | 15,106,048 B | `0d2966a10e8429864e5e337d568d66286a9727f6cb1957b0d7c1fa83fbc02092` ✓已核 |
| 3 | v12 | `out/boot_r11s_phase3_reviewfix_v12.img` | 15,101,952 B | `c93e00397ae98be09bc72f07779d25acb105142e1b0509e4831d9d8dfa69cc63` |
| 4 | v11 | `out/boot_r11s_phase3_audio_v11.img` | 15,101,952 B | `a07a5ef5…`（完整值见 v11 归档 SHA256SUMS） |
| 5 | v10 | `out/boot_r11s_phase4_rootfs_v10.img` | 15,081,472 B | `28773a5cf8174287572e9043f1581f01f9b06dd2e1318557a71d0fb6a9adbb3c` |
| 6 | v9 | `out/boot_r11s_phase3_integrated_v9.img` | 15,081,472 B | `c34f1307…`（完整值见 v9 归档 SHA256SUMS） |
| 7 | **终极回滚** | `boot-debug.img` | 20,717,568 B | `4ff811c37070540f0d0fa8fcb1c49d14ee44f3a4e62991fe761f0b1e08d1a7a4` ✓已核 |

> 标 ✓ 者为本会话实测核验；其余引自 STATUS.md，刷写前建议复核归档 SHA256SUMS。
> **回滚链缺口提醒**：STATUS.md:286 / :349 记载的链条均**漏了 v10**，而 v10 是唯一切根镜像。本表已补全。

---

## 四、待授权命令（**未执行，等用户当次明确确认**）

### 4.1 刷写 v14

```bash
# 目标分区：boot（64MiB raw）
# 前置：设备处于 fastboot（18d1:d00d）
fastboot flash boot /home/<user>/claude/r11/out/boot_r11s_v14.img
fastboot reboot
```

**风险与预期**：
- p69 **尚未格式化** → 预期行为 = 切根失败、落回救援 shell（这是防砖验证，属正常）。
- `deferred_probe_timeout=30` 对 D1（RCG warning）**零收益**，只对 D6（bind 不起来）兜底。
- 若改了 GPU 供电（B-4），风险显著升高，建议**单独出包单独刷**。

### 4.2 回滚（任一环节异常时）

```bash
fastboot flash boot /home/<user>/claude/r11/boot-debug.img      # 终极回滚，回 Lineage
fastboot flash boot /home/<user>/claude/r11/out/boot_r11s_phase3_regdiag_v13.img   # 回 v13
```

### 4.3 格式化 p69 + 写 rootfs（**需单独当次确认，脚本内置双重确认**）

```bash
# 脚本默认干跑，需用户双重确认
bash /home/<user>/claude/r11/tools/r11s_phase4_emmc_setup.sh
```

---

## 五、刷前检查清单

- [ ] v14a 的代码改动已全部落地并重编译（若本轮采纳）
- [ ] 三份原料 sha256 与本文第一节一致
- [ ] dry-run 预测 hash == `--write` 实际 hash
- [ ] 解压后 Image ≤ 0x3000000（期望 39,174,656 B）
- [ ] header 逐字段与 v13 对比，差异仅限 kernel/ramdisk size + cmdline
- [ ] DTB 反编译回读：panel@0 okay、panel@1 disabled
- [ ] ramdisk 内 `/init` 可执行且含 `mmcblk1p69`（v10 切根语义）
- [ ] 归档已写入 `backups/products/products_r11s_v14_<ts>/` 并含 SHA256SUMS
- [ ] 回滚链 7 项全部在位（至少 `boot-debug.img` 已核验）
- [ ] **已取得用户当次明确的"刷"授权**
