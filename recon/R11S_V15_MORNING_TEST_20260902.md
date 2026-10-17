# v15 明早测试清单（2026-09-02）

> 镜像：`out/v15/boot_r11s_v15.img`（`f944aaf7a6d076…`，37,220,352 B）
> 刷写命令（**需当次授权**）：`fastboot flash boot out/v15/boot_r11s_v15.img && fastboot reboot`
> 回滚：`out/v14b/boot_r11s_v14b.img` → `out/boot_r11s_phase3_regdiag_v13.img` → `boot-debug.img`
> 交互：启动后约 20–40s 出现 `/dev/ttyACM0`，用 `bash tools/acm_cmd.sh '<cmd>'` 取证（ramdisk 变大，启动会慢一些）。
> 抓全量 dmesg：`dmesg | gzip | base64 -w 100 > /tmp/d15.b64; wc -l /tmp/d15.b64`，然后分段 `sed -n` 下载。

## A 组 · 显示时钟（V1，本轮核心）

| 检查 | 命令 | 预期 |
|---|---|---|
| A1 | `dmesg \| grep -c "rcg didn't update"` | **0**（v14b 是 2 次，都是 pclk0） |
| A2 | `dmesg \| grep -i "DSI PLL lock failed"` | 无。若有 → V1 需叠加 DSI 侧补丁（xfer_prepare 前置 power_on），记录次数 |
| A3 | `cat /proc/fb; ls /dev/dri` | `0 msmdrmfb` + `card0 renderD128` 仍存在 |
| A4 | `dmesg \| grep -iE "failed to set rate pixel clk\|Power on failed"` | 无 |

## B 组 · 双面板自动检测（C-4）

| 检查 | 命令 | 预期 |
|---|---|---|
| B1 | `dmesg \| grep "R11s panel autodetect" ` | sofeg01 侧出现 `selected by ABL cmdline` |
| B2 | `dmesg \| grep "not the ABL-selected panel"` | ams596 侧（`c994000.dsi.1`）出现 → **门控生效**，证明未同时 attach、VC 未被覆盖 |
| B3 | `cat /proc/fb` + 实际观屏 | 显示正常亮起（与 v14b 一致） |
| B4 | `dmesg \| grep -iE "sofeg01\|panel-samsung"` | sofeg01 probe/prepare/enable 无新增错误 |

## C 组 · 触摸

| 检查 | 命令 | 预期 |
|---|---|---|
| C1 | `cat /proc/bus/input/devices \| grep -A2 s3508` | 若本轮传感器窗口正常：`N: Name="Synaptics s3508"` 出现 |
| C2 | `dmesg \| grep -c "deferring probe"` | ≤2；且**绝不再出现无限循环**（观察 60s 后计数不再增长） |
| C3 | `dmesg \| grep -E "giving up\|F12 disabled"` | 若描述符再读不出：最多 1 条放弃记录，系统稳定不崩 |

## D 组 · 音频（首次具备可测性）

| 检查 | 命令 | 预期/说明 |
|---|---|---|
| D1 | `dmesg \| grep -iE "remoteproc1\|adsp"` | 重点：固件 -2 应消失，出现 ADSP 启动（boot/shutdown/remote processor up） |
| D2 | `dmesg \| grep -iE "q6core\|apr\|q6afe\|q6asm"` | APR 服务是否注册 |
| D3 | `mount -t debugfs none /sys/kernel/debug; cat /sys/kernel/debug/devices_deferred` | 若 ADSP 起来，`sound` 的 `MultiMedia1: error getting cpu dai name` 应消失或变化 |
| D4 | `dmesg \| grep -iE "cdsp\|remoteproc2"` | cdsp 不再 -2（本轮把 cdsp 放到了固件根目录以匹配无前缀请求） |
| D5 | `dmesg \| grep -iE "snd\|sdm660-int-sndcard\|wcd"` | 声卡是否注册（aplay/lsmod 无 alsa-utils，先以 dmesg 判定） |

## E 组 · GPU / WiFi（预期仍失败，记录具体错误）

| 检查 | 命令 | 预期 |
|---|---|---|
| E1 | `dmesg \| grep -iE "a530_pm4\|a530_pfp"` | 微码加载成功（v14b 已达成，保持） |
| E2 | `dmesg \| grep -iE "zap\|gpu hw init"` | 仍 `Unable to load a512_zap.mbn` → gpu hw init -2（**已知，未解决**：无合法固件源） |
| E3 | `dmesg \| grep -iE "ath10k\|wlanmdsp\|firmware-5"` | 现在应能取到 firmware-5.bin；注意是否报版本/fatal（社区 1.0.0.533 教训）；modem 未在 ramdisk，WiFi 大概率仍失败 → 属预期 |
| E4 | `dmesg \| grep -iE "supply vdd-3.3-ch"` | ch1 的 dummy 告警应消失（本轮补了 DTB 属性） |

## F 组 · 稳定性与切根

| 检查 | 命令 | 预期 |
|---|---|---|
| F1 | `uptime` / 观察 90s | 无重启、无 panic、无 hung task |
| F2 | `dmesg \| grep -c .` | 日志量稳定（不再有 v13 的无限刷屏） |
| F3 | `cat /proc/partitions \| tail -3` | p69 在位（23.2GB，未格式化） |
| F4 | 切根行为 | **预期落回救援 shell**（p69 未格式化）；这是防砖验证，正常 |

## 判定口径

- 通过的项 → 合并进主干，更新 STATUS/HANDOFF。
- 失败项分两类：① 有明确下一步（如 A2 出现 → 叠加 DSI 侧补丁）→ 进 v16 a 批；② 缺外部资源（zap / modem / 第二台变体机）→ 标「未取证」，不在本树凭推测实现。
- 任何一项若导致**显示不亮或无法进救援 shell**，立即回滚 v14b 并保留 dmesg。
