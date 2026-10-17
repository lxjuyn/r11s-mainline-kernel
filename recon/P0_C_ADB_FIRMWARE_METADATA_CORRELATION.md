# P0-C 补充：实机 vendor 元数据与 C.19 候选的只读关联

**取证日期：2026-07-30**  
**方式：** ADB 只读 `getprop`、可读的设备树 bootargs、缓存/OTA 路径元数据检查。未读取分区内容、未下载固件、未写设备。  
**原始目录：** `recon/p0_adb_firmware_metadata_20260730_141303/`。

## 原始观察

| 字段 | 实机值 | 解释边界 |
|---|---|---|
| `ro.product.model` | `OPPO R11s` | 与已确认的 R11s（无 t、中国大陆公开版）一致。 |
| `ro.dot.releasetype` | `For OPPO R11s` | DotOS 属性，只能证明当前 ROM 的目标声明，不能证明原厂版本。 |
| `ro.build.fingerprint` | `OPPO/R11s/R11s:9/PKQ1.190414.001/1588166940:user/release-keys` | Android 9 / R11s 格式的遗留 fingerprint；具体来自哪个原厂构建未证实。 |
| `ro.vendor.oppo.build.id` | `PKQ1.190414.001` | 当前 vendor 层的 OPPO 构建标识；不能单独映射为 C.19。 |
| `ro.vendor.build.date` | `Fri May 22 19:02:29 CST 2020` | 当前 vendor 层时间戳；与候选 C.19 的页面时间接近，但不构成来源或完整性证明。 |
| `ro.vendor.build.security_patch` | `2020-05-05` | 当前 vendor 层补丁字段；不能确定为原厂 C.19 的官方发布日期。 |
| DT bootargs | `mdss...oppo17011...`、`androidboot.bootdevice=c0c4000.sdhci` | 与 R11s/17011 的实机硬件锚点一致；不是固件版本证据。 |

## OTA 缓存检查结果

- 可访问的 `/cache/recovery` 不存在；
- `/metadata` 与 `/metadata/ota` 不存在；
- `/data/cache/recovery` 无 shell 权限；
- 在 shell 可读取范围内，未发现 `.ozip`、`.zip`、`.ofp` 或 `payload.bin` 候选文件。

因此，**设备上没有可由本次非 root ADB 读取的缓存 OTA 包或恢复日志可用于验证 C.19。** 这不能说明这些文件绝对不存在，只说明在当前权限和已探测路径下未获得它们。

## 与网络候选的关联判断

此前第三方候选记录的是 `R11s_11_OTA_1190_all_Vv6yB9efD2ry.ozip`，标注 ColorOS 6.0.1 / Android 9 / C.19，页面时间为 2020-12-31，且给出单一第三方 MD5。实机当前 vendor 显示 Android 9 时代的 OPPO ID、2020-05 vendor timestamp 和 2020-05-05 patch；这使其与 **Android 9 / ColorOS 6 世代** 相容。

但时间戳并不等于构建号，当前 vendor 也可能由早于或不同于 C.19 的原厂构建保留。因此，以下结论禁止成立：

- 禁止声称实机当前 vendor 来自 C.19；
- 禁止把 `e9aee976b7c4559ae4ca977b727ef117` 当作官方校验值；
- 禁止仅凭 fingerprint 或 vendor 日期下载/接受第三方候选作为回滚材料。

## P0-C 状态

候选文件名、版本线索与实机 Android 9 vendor 世代相容，但**原厂来源链、原始文件 hash、签名和包内容全部未验证**。P0-C 保持进行中；下载与解包门禁不变。
