# DOMAIN_wireless — WiFi / 蓝牙 / 外设固件域

> Wave 1 · 子代理只读取证 · 2026-09-02 · 完整证据链见 `LEDGER_v14_20260902.md` F11、F17-F19

## 结论

1. **WiFi 供电配置完整**：`wifi@18800000` 四路供电齐全且 `status = "okay"`，与社区参考一致，不存在缺供电问题。
2. **固件路径存在硬不匹配**：驱动请求 `ath10k/WCN3990/hw1.0/firmware-5.bin`，但该目录只有 `board-2.bin` + `wlanmdsp.mdt/b03/b04/b06/b07`，**没有 firmware-5.bin**；原厂 `wlanmdsp.mbn` 被孤立在 `archive/` 未改名安装。
3. **BT 的 `crbtfw21.tlv` 是"ramdisk 未打包"而非"路径不一致"**：清单相对路径与内核请求字符串逐字相同，与 adsp/cdsp 同为 ENOENT(-2)，同一根因。
4. **modem 链路已具备**：`remoteproc@4080000` = `qcom,sdm660-mss-pil`，`status = "okay"`，`firmware-name = "mba.mbn\0modem.mdt"`，清单里这两个文件正位于 `firmware/` 根（无前缀），路径**匹配**。
5. **社区 2–4 条教训需作为 v14 上板前置项消化**：R11s 的 WiFi 固件来自原厂 OTA 解包的 `archive/wlanmdsp.mbn`（很可能即 1.0.0.533 / htt-ver 3.50 一档），未做版本核对前上板，预期命中"WiFi 起后约 350ms fatal error"。

## 证据

**WiFi 节点供电（4 路齐全）** — `dtb_v12.verify.dts:3140-3156`
```dts
3140:	wifi@18800000 {
3141:		compatible = "qcom,wcn3990-wifi";
3148:		iommus = <0x2d 0x1a00 0x2d 0x1a01>;
3149:		qcom,snoc-host-cap-8bit-quirk;
3150:		qcom,no-msa-ready-indicator;
3151:		status = "okay";
3152:		vdd-0.8-cx-mx-supply = <0x96>;
3153:		vdd-1.8-xo-supply = <0x7d>;
3154:		vdd-1.3-rfa-supply = <0x7e>;
3155:		vdd-3.3-ch0-supply = <0x7f>;
3156:	};
```

**BT 节点（与 WiFi 共享 3 路 regulator，多一路 vddio）** — 同文件 `:2602-2611`
```dts
2604:		bluetooth {
2605:			compatible = "qcom,wcn3990-bt";
2606:			vddxo-supply = <0x7d>;
2607:			vddrf-supply = <0x7e>;
2608:			vddch0-supply = <0x7f>;
2609:			vddio-supply = <0x80>;
2610:			max-speed = <0x30d400>;
```
`0x7d/0x7e/0x7f` 与 WiFi 的 xo/rfa/ch0 为同一 regulator → 单芯片共享电源，交叉验证两节点 regulator 编号未错位。

**内核请求的固件路径** — `drivers/net/wireless/ath/ath10k/hw.h:125,138` + `core.c:724,1325,1679`
```c
125:#define WCN3990_HW_1_0_FW_DIR		ATH10K_FW_DIR "/WCN3990/hw1.0"
138:#define ATH10K_FW_API5_FILE		"firmware-5.bin"
```
→ 最终请求串：`ath10k/WCN3990/hw1.0/firmware-5.bin` 与 `ath10k/WCN3990/hw1.0/board-2.bin`

**清单实际内容（关键不匹配）** — `firmware/ath10k/WCN3990/hw1.0/`
```
board-2.bin (468.65 KB)          ← ✅ 匹配
wlanmdsp.b03 (2.71 MB)  wlanmdsp.b04 (240.54 KB)
wlanmdsp.b06 (2.44 KB)  wlanmdsp.b07 (17.34 KB)  wlanmdsp.mdt (340 B)
firmware-5.bin                   ← ❌ 缺失
```

**原厂 WiFi 固件被孤立在 archive/** — `firmware/archive/`
```
archive/wlanmdsp.mbn (3.32 MB)
archive/bdwlan_variants/bdwlan.bin, bdwlan.b04/.b07/.b09/.b0a/.b0b/.b0d/.b0e/.b0f/.b14/.b30~.b37, bdwlan.102~.109
```
（`bdwlan_variants/` 是下游 wcnss 的 board-data 变体系列，主线 ath10k 不用此路径）

**BT 固件（路径字符串一致）** — `firmware/qca/`
```
qca/crbtfw21.tlv (113,976 B)   ← 与日志请求串逐字相同
qca/crnv21.bin   (4.39 KB)
```

**modem/remoteproc 节点** — `dtb_v12.verify.dts:1470-1496`、`:788-792`
```dts
1470:	remoteproc@4080000 {
1471:		compatible = "qcom,sdm660-mss-pil";
1483:		power-domains = <0x32 0x00 0x32 0x03>;
1484:		power-domain-names = "cx\0mx";
1486:		status = "okay";
1487:		firmware-name = "mba.mbn\0modem.mdt";
1490:		glink-edge { label = "modem"; qcom,remote-pid = <0x01>; };
```
清单侧：`mba.mbn`(236.67 KB)、`modem.mdt`(8.21 KB)、`modem.b00~b28` 均在 `firmware/` 根 → **匹配**

**SMP2P 三路就绪** — 同文件 `:820-846`、`:3567-3571`
```dts
smp2p-adsp / smp2p-mpss / smp2p-cdsp  三路全在
```

**GPU zap（顺带核对）** — 同文件 `:1570-1573`
```dts
1570:		zap-shader { memory-region = <0x3a>; firmware-name = "a512_zap.mbn"; };
```

## 补丁级定位

| # | 位置 | 改法 | 收益 | 风险 |
|---|---|---|---|---|
| **A-5** | `firmware/ath10k/WCN3990/hw1.0/`（新增） | 把 `archive/wlanmdsp.mbn` 另存副本为 `firmware-5.bin`（保留原件） | 消除路径硬不匹配 | 无变砖风险；版本不对则进 W3 场景 |
| **A-6（先做）** | 只读取证 | `strings -n 6 archive/wlanmdsp.mbn \| grep -iE '1\.0\.0\.[0-9]{3}\|htt-ver'` | 把 W3 从概率变确定 | 无 |
| **A-7（条件）** | 整组替换 | 取 whyred V12 NON-HLOS.bin，替换 wlanmdsp + mba + modem.b* + adsp.b* + cdsp.b* | 规避 350ms fatal error | 误配 → modem watchdog timeout（不砖） |
| **A-8** | 救援 ramdisk 打包清单 | 加 `qca/crbtfw21.tlv` + `qca/crnv21.bin` | BT 切根前可用 | +116KB（可接受） |
| P5 | `dtb:2604-2611` | 显式补 `status = "okay"`（可选，消除可读性歧义） | 可读性 | 极低 |
| P7 | 测试流程 | **冷启动**验证，禁止 warm reboot 后判定 WiFi 成败 | 避免误判 | 无 |

**⚠ 不要做**：给 modem 固件加 `qcom/sdm660/` 前缀——本 DTB 的命名（modem 无前缀 / adsp·cdsp 有前缀）与清单实际布局**均一致**，照抄社区教程会引入新 ENOENT。

## 未取证

1. **未找到** `firmware/ath10k/WCN3990/hw1.0/firmware-5.bin`（本轮最关键缺口）。
2. **未找到** `NON-HLOS.bin` 本体；无法追溯 `archive/wlanmdsp.mbn` 的来源 OTA 版本。
3. **未执行** `strings` 抽取 → `wlanmdsp.mbn` 的版本号与 htt-ver **本轮未取得**，社区教训只能映射为风险、不能确认命中。
4. **未读到** `remoteproc@1a300000`（cdsp, `:3170`）的 `firmware-name` 行 —— cdsp 固件名与 status 需补查。
5. **未读写** v13 dmesg 原文 → **mss/mba/modem 的固件加载行未核实**：无法确认 v13 实机 modem 是否真正起来。
6. **未校验** `crbtfw21.tlv` 字节一致性（111.3 KB vs 113,976 B 差 5 B，判为 ls 取整所致，未做 sha1 交叉验证）。
7. **未证实** BT 为何请求 `crbtfw21.tlv`：WCN3990 主线通常不走 ROME rampatch 流程，提示 hci_qca 可能按 ROME 分支处理（或 DTS 缺 soc 类型区分）。**存疑，需另开一路核实**。
8. 未找到主线常见的 `qcom,msa-mem` / `wlan-firmware-name` 属性与 staging 分区挂载配置。

## 与既有事实的冲突

| ID | 双方证据 | 仲裁 |
|----|----------|------|
| C1 | 社区「主线 WiFi ✅ Works」vs 本项目 firmware-5.bin 缺失 | **不冲突**。主线支持为"是"，本项目缺口在**固件打包/来源**，非驱动能力 |
| C2 | 日志 `qca/crbtfw21.tlv -2` vs 清单存在该文件 | **非冲突**。路径逐字一致；"清单有但加载失败"是**两个不同文件系统快照**（清单 = rootfs 全量；失败发生在救援 ramdisk） |
| C3 | DTB 内 modem 无前缀 vs adsp/cdsp 有前缀 | **非冲突**，两侧都对得上。但需记录为本 DTB 沿用 downstream 命名风格，**不要**照抄社区给 modem 加前缀 |
| C4 | 社区「WiFi 依赖 modem DSP」vs v13 日志只报 adsp/cdsp 失败 | **不冲突**（mss 无报错 = 未请求或已成功），但**无法确证 modem 真正起来了** → v14 必须第一时间抓 `remoteproc0`/mss 加载行 |
