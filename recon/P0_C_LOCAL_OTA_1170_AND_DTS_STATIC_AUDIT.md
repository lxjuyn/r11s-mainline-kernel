# P0-C 补充：用户提供 R11s_11_OTA_1170.zip 与 DTS 的主机侧静态审计

**审计日期：2026-07-30**  
**范围：** 仅对用户本地主机已存在的文件做静态、只读检查；未执行 ZIP 内脚本、未调用 recovery/update-binary、未向设备发送命令、未提取或写入任何分区镜像。

## 输入、来源与完整性边界

| 项目 | 值 |
|---|---|
| OTA 本地路径 | `/home/<user>/claude/r11/R11s_11_OTA_1170.zip` |
| OTA 大小 | `2,596,106,598` bytes |
| OTA SHA-256 | `748a8246cb0f7930cf6cf7851b3b3fa21f7dd9f9fd8ed4fc414f90b2eeb41d39` |
| DTS 本地路径 | `/home/<user>/claude/r11/r11s..dts` |
| 用户给出的下载页 | `https://www.yhcres.top/02-%E6%89%8B%E6%9C%BA%E5%B9%B3%E6%9D%BF/OPPO/R%E7%B3%BB%E5%88%97/OPPO%20R11s` |

给出的页面是非 OPPO/ColorOS 官方域名。MCP 对该页的提取只获得广告确认层，未取得可核验下载文件、文件 hash、OPPO CDN 链接或官方签名链。因此该 URL **不能建立官方分发来源链**。

## OTA 内容确认

`META-INF/com/android/metadata` 直接声明：

```text
ota-id=R11s_11.A.17_1170_202005221816
ota_version=R11s_11.A.17_1170_202005221816
version_name=R11s_11_C.17
pre-device=R11s
google_patch=20200505
post-timestamp=1590145533
ota-type=BLOCK
wipe=0
```

静态读取的 `META-INF/com/google/android/updater-script` 以 `ro.product.device == "R11s"` 和 `ro.product.name == "R11s"` 作为安装前断言。它引用 `boot`、`system`、`vendor` 以及一组 Qualcomm 固件分区；这是**包内脚本的声明**，不表示本项目已执行、也不表示设备已兼容或允许安装。

归档中实际出现 `boot.img` 和 `firmware-update/` 下的固件文件；未出现 `recovery.img`、`vbmeta.img` 或 `dtbo.img`。这只描述这个 C.17 包的实际清单，**不能**外推其他原厂包或实机分区布局。

`boot.img` 静态指标：

```text
SHA-256: 790396edc79390215227c81356851f545ac0c00d829da684364193a6f79a9520
magic: ANDROID!
header_version field: 1
page_size: 4096
kernel_size: 15484019
ramdisk_size: 0
```

该 header 字段读数只对这个包内的 `boot.img` 有效，不能替代对实机当前 boot 或未来其他原厂包的解析。

## ZIP 内部签名与完整性检查

- `unzip -t` 的 ZIP CRC 检查通过。
- 245 个已列入 `META-INF/MANIFEST.MF` 的 payload 条目，重新计算 SHA-1 后均与清单一致。
- `CERT.RSA` 对 `CERT.SF` 的 CMS/PKCS#7 detached signature 验证成功。
- 证书主体和颁发者均显示 `O=Android, OU=Android, CN=Android, emailAddress=<EMAIL>`，证书有效期为 2017-02-20 至 2044-07-08。

这证明**当前归档的签名结构、清单和 payload 相互一致**，且签名证书包含 `<EMAIL>` 标识；它不能单独证明下载站的交付链、也不能在未获得 OPPO 官方信任锚/官方发布记录的情况下证明该文件就是 OPPO 官方发布物。因此它仍不是满足项目回滚门禁的“已核验原厂材料”。

## DTS 与实机 17011 的关系

用户提供的 DTS 根节点为：

```dts
model = "Qualcomm Technologies, Inc. SDM 660 PM660 + PM660A MTP";
compatible = "qcom,sdm660-mtp", "qcom,sdm660", "qcom,mtp";
qcom,board-id = <0x08 0x00 0x427d>;
```

`0x427d` 十进制为 **17021**。已取得的实机 live DT board-id 是 **17011** (`0x4273`)。两者不是同一个 board-id。

用户补充说明：**17021 DTS 在其实际使用经验中可以用于本机。** 这是一项有价值的兼容性线索，说明不能仅凭 board-id 差异就推断它必然不可启动或完全无参考价值；本报告此前“不得直接移植”的绝对表述据此撤回。

但当前项目尚未在本机对该 DTS 做过构建、`fastboot boot` 或刷写测试，且当前安全门禁禁止生成或测试镜像。因此，该经验尚不能升级为“17021 DTS 已由本项目在 17011 实机验证可用于主线 Linux”的结论。应将其标为：**用户声明的下游兼容性证据**。在未来满足原厂回滚材料和测试门禁后，仍须通过最小化、非破坏性的实际启动验证，逐项确认 USB、eMMC、PMIC/regulator、面板及其他板级差异。

该 DTS 的 `ssusb@a800000`、`dwc3@a800000`、`qusb@c012000`、`hsusb@c200000` 和 `sdhci@c0c4000` 节点地址与此前 live-DT / SDM660 参考锚点属于同一 SoC 地址族。它们可与上述用户兼容性线索一起作为参考；供电、GPIO、pinctrl、角色检测、面板和存储时序仍必须以 17011 live DT、可核验原厂 17011 材料或后续受控实机验证逐项确认。

特别地：此 DTS 未见 `ramoops` 节点；这不证明实机或其他固件不存在 pstore/ramoops。

## 结论与 P0-C 状态

1. 本机已取得一个内部一致、目标字符串为 `R11s`、版本为 **C.17 / 1170 / 2020-05-22** 的本地 OTA 归档证据。
2. 它不是先前 C.19 候选；不得将 C.17 与 C.19 混为同一版本，也不得将此前第三方 C.19 MD5 用于校验此文件。
3. 包内签名的自洽性不足以替代官方来源链；给出的 yhcres 页面不能提供该来源链。
4. 该 OTA 不提供 `dtbo.img`，但不能据此断言设备不存在或不使用 dtbo 分区；现有实机 ADB/fastboot 结果仍是“dtbo 未证实”。
5. `vbmeta.img` 未在此 OTA 中出现，不能据此推断 AVB 策略或设备接受条件。
6. P0-C 的“官方、可回滚材料”门禁仍未满足；禁止将此归档用于写入、刷机、fastboot boot、EDL 或任何设备状态改变操作。
