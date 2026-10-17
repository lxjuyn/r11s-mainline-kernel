# R11s fastboot 只读取证报告

**取证日期：2026-07-30**  
**采集方式：** `adb reboot bootloader` 进入 fastboot 模式，`fastboot getvar` 只读查询，`fastboot reboot` 退出。全程未 flash、未 boot 临时镜像、未写分区。  
**取证目录：** `recon/p1_fastboot_readonly_20260730_040128/`

---

## 1. 关键结论：bootloader 已解锁，但 fastboot 能力有限

### 1.1 unlock 状态（实测澄清，推翻 ADB 矛盾值）

| 变量 | 值 | 说明 |
|---|---|---|
| `unlocked` | **yes** | bootloader 真实状态：**已解锁** |
| `secure` | yes | secure boot 已启用；仅凭该变量与 `unlocked=yes` 不能推断 AVB 策略或非原厂镜像接受条件 |
| `hw-revision` | 10000 | 硬件版本 |
| `product` | sdm660 | 确认平台 |
| `variant` | SDM EMMC | 确认 eMMC 配置 |
| `kernel` | uefi | bootloader 类型（UEFI/ABL，Qualcomm aboot 链） |
| `serialno` | 9144dacf | 与 ADB 一致 |

**这澄清了 ADB 的矛盾**：ADB 报 `flash.locked=1 / verifiedbootstate=green` 与 fastboot bootloader 层的 `unlocked=yes` 相互矛盾。这些 Android 属性的具体来源未证实，不能单独采信；以 fastboot 实测的 `unlocked=yes` 记录 bootloader 状态。

### 1.2 fastboot 能力评估（重要）

本次 `getvar all` 返回了**完整的分区表与大小**（156 行），但**缺失多个标准 A/B 与能力探测键**：

| 查询 | 结果 |
|---|---|
| `current-slot` / `slot-count` | **Variable Not found** |
| `has-slot:boot` / `has-slot:system` | **Variable Not found** |
| `partition-type:dtbo` / `partition-size:dtbo` | **Variable Not found** |
| `version-bootloader` / `version-baseband` | 空（未实现） |
| `os-version` | Not found |

**结论：**
1. **此 bootloader 的标准 A/B slot 查询未实现或未暴露**（`current-slot`/`slot-count` 均未找到）。分区表中存在 `bootbak`、`vbmetabak` 等名称相似的备份分区，但其实际更新/回退语义未由本次只读查询证实；不得将其称为 A/B slot 或确定的“双备份方案”。
2. `dtbo` 在 fastboot 中未暴露，且 ADB by-name 分区表（69 个分区）中亦未见 `dtbo` 符号链接。这表示设备分区布局可能不含 `dtbo`，或该组件采用其他命名；在取得原厂固件包的分区清单前不得假设其存在。
3. `max-download-size: 536870912`（512 MiB）——bootloader 接受 download 内存上限。
4. **`fastboot boot`（临时启动）是否支持——本次未实测。** bootloader 未暴露可推断该能力的 getvar 键。按 CLAUDE.md 红线，**没有实测 `fastboot boot` 的成功响应前，不得假设它支持临时启动**。实测它需要真正发起一次 `fastboot boot` 命令加载一个镜像——这属于"会改变设备运行状态"的操作，需单独当次批准。

## 2. fastboot 可见分区表（一手，bootloader 权威）

分区布局与 ADB by-name 完全一致，且 fastboot 给出精确大小：

| 分区 | 大小 | 类型 |
|---|---|---|
| xbl / xblbak | 0x380000 | raw（一级 bootloader） |
| tz / tzbak | 0x400000 | raw（TrustZone） |
| hyp / hypbak | 0x80000 | raw |
| rpm / rpmbak | 0x80000 | raw |
| pmic / pmicbak | 0x80000 | raw |
| abl / ablbak | 0x100000 | raw（Android bootloader，UEFI） |
| **boot / bootbak** | 0x4000000 (64 MiB) | raw |
| **recovery** | 0x4000000 (64 MiB) | raw |
| **vbmeta / vbmetabak** | 0x10000 (64 KiB) | raw |
| dsp / dspbak | 0x1000000 | raw |
| modem | 0x8000000 (128 MiB) | raw |
| system | 0x131300000 | ext4 |
| vendor | 0x7A100000 | raw |
| cache | 0x10000000 | ext4 |
| userdata | 0xB95FFC000 | f2fs |
| persist | 0x2000000 | raw |
| modemst1 / modemst2 / fsg / fsc | 0x200000 / 0x200000 / 0x200000 / 0x400 | raw |
| (其余 frp/devcfg/keymaster/cmnlib/mdtp/dip/dpo 等) | 各异 | raw |

**关键：**
- `boot` = 64 MiB，`recovery` = 64 MiB，`vbmeta` = 64 KiB。
- 标准 A/B slot 查询未实现或未暴露；可见 `bootbak`/`vbmetabak` 等备份命名分区，但其语义未证实。
- `splash` = 0x20A4000（含开机 logo）。
- `dtbo` 在 fastboot getvar 与 ADB by-name 分区表中均未出现；设备布局是否含该分区尚未证实。原厂固件包解包后，应先检查分区清单，再决定是否存在可提取的 `dtbo.img`。

## 3. 对主线移植策略的影响

1. **解锁状态已记录**：`unlocked=yes`；但仅靠这一变量不能推断非原厂 boot 镜像的接受或启动条件，须待原厂 boot/vbmeta 和实际 bootloader 行为取证。
2. **临时启动路径未定**：`fastboot boot` 是否支持仍未实测。其支持与否、任何未来镜像启动或分区写入均须在具备完整经 hash 校验的原厂回滚材料后，另获用户当次明确授权。
3. **boot 分区 64 MiB**：足够容纳主线 arm64 内核 + 简单 initramfs。
4. **vbmeta 存在**：是否使用 AVB、其版本及具体验证策略均待原厂镜像解包确认；不得据此预设任何修改或关闭验证的流程。

## 4. 下一步取证门禁

- **P0-C（原厂固件下载与解包）**：继续从可核验渠道获取与已确认型号匹配的 **R11s（无 t、中国大陆公开版）** 原厂 ColorOS 固件包。记录来源、完整性信息和 SHA-256，解包仅取证 boot/recovery/vbmeta 及实际分区清单；`dtbo` 只有在包内清单出现时才作为取证对象。这也是获得可验证原厂回滚材料的必要步骤（当前设备 boot 已被 DotOS 覆盖）。
- **`fastboot boot` 实测**：在拿到主线内核镜像后，单独当次批准下实测是否支持临时启动。现在没有镜像可测。
- 设备精确型号已由用户确认并由 `ro.product.model=OPPO R11s` 佐证：**R11s（无 t、中国大陆公开版）**；不是 CPH1719 国际版，也不是 R11st 中国移动定制版。

## 5. 文件清单

- `fastboot_getvar_all.txt` — 完整 getvar all 输出
- `fastboot_getvar_supp.txt` — 补充能力探测（slot/dtbo/version）
