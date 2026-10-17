# P0-C 补充：用户提供 C.19 通刷底包的静态完整性审计

**审计日期：2026-07-30**  
**方式：** 仅主机侧读取 ZIP 目录、控制文件、签名容器和文件 hash；没有执行包内脚本、没有提取镜像、没有连接或操作设备。

## 输入身份

```text
路径: /home/<user>/claude/r11/R11s_C19_通刷底包_无需补丁.zip
大小: 558,273,483 bytes
SHA-256: 5d530907c2de873edc5841ca5ef12c2efef7234bbe026d318c27052e0da6fe57
ZIP CRC: 通过
```

文件名中的“通刷底包/无需补丁”仅是交付者命名，不是官方性、设备兼容性或安全性证明。

## 包内版本声明

`META-INF/com/android/metadata` 声明：

```text
google_patch=20200905
ota-id=R11s_11.C.19_1190_202010310009
ota_version=R11s_11.C.19_1190_202010310009
post-timestamp=1604076874
pre-device=R11s
version_name=R11s_11_C.19
wipe=0
```

这确认归档内部的 metadata 自称是 R11s 的 C.19 / 1190 / 2020-10-31 版本；它不是 OPPO 官方发布记录或下载来源证明。

## 包实际清单与脚本声明

归档顶层有 `boot.img`、`vendor.img`、`firmware-update/` 和 `META-INF/`，共 38 个成员。没有 `recovery.img`、`vbmeta.img`、`dtbo.img`。

`updater-script` 声明会写入 `boot`、`vendor` 和多项 Qualcomm 固件分区及其备份分区。该脚本没有被执行。其写入声明不能被当作本项目对实机分区、兼容性或可刷写性的结论。

包内对象 hash：

```text
boot.img SHA-256: e4e6f63cb4978e1c023383c3237a5f5917dfdf43188ae69d590be43ef5e010d2
vendor.img SHA-256: 1fb88ae181dd7fb3088e9f00656ff9cb3e828650a92046ec5c25b75ac7fde4d5
boot magic: ANDROID!
boot header_version field: 1
boot page_size: 4096
```

`dtbo.img` 和 `vbmeta.img` 未在此 ZIP 出现，不支持对实机 `dtbo` 是否存在或 AVB 策略作任何推论。

## 严重完整性问题

ZIP 层 CRC 检查通过，且 `CERT.RSA` 对 `CERT.SF` 的 CMS detached signature 验证成功；签名证书 Subject/Issuer 均含 `emailAddress=<EMAIL>`。

但对 `META-INF/MANIFEST.MF` 逐项重算 SHA-1 后，发现归档**不具备完整的 JAR/OTA payload 完整性**：

- `MANIFEST.MF` 声明 244 个 payload 条目；
- 其中大量声明条目实际不在 ZIP 中（包括 data_update_patch、system/vendor dat 文件等）；
- 15 个实际存在的重要条目与其 Manifest SHA-1 不匹配，包括 `boot.img`、`firmware-update/abl.img`、`xbl.img`、`tz.img`、`modem.img`、`keymaster.img` 等；
- `vendor.img` 是实际存在但未列入 Manifest 的 payload。

因此，证书只能证明 `CERT.SF` 本身与其签名容器一致，**不能证明当前 ZIP 中的 boot/vendor/firmware payload 与被签名的 Manifest 一致**。该 C.19 归档应标为：**内部 metadata 自称 C.19，但 payload 签名完整性验证失败/不完整，禁止用于回滚、提取原厂事实、测试或任何写入。**

这比“无官方来源链”的问题更直接：即使未来出现同名第三方来源，也不能以该文件取代完整、可验证的官方归档。

## 与此前 C.19 第三方候选的边界

此前第三方页面记录的 OTA 文件名是 `R11s_11_OTA_1190_all_Vv6yB9efD2ry.ozip`，其第三方 MD5 是 `e9aee976b7c4559ae4ca977b727ef117`。本归档的文件名、容器形式和 SHA-256 均不同，且内部 manifest 校验异常；不得把那一个第三方 MD5 用来证明本文件，也不得把本文件当作前述候选 OTA 的同一字节内容。

## 结论

P0-C 官方、可回滚材料门禁仍不满足。禁止解包、执行脚本、生成镜像、fastboot boot、刷写、EDL、解锁或写入。
