# R11s 接力交接 — 全 Linux 达成 + 剩余驱动清单（2026-09-03）

> 一句话：**OPPO R11s 已跑通完整 Ubuntu 24.04 + systemd，SSH over USB ECM 可用**（v17 切根成功）。
> 剩余 = WiFi（卡在 modem 崩溃，头号嫌疑 rmtfs 未跑）、音频实放验证、BT、双面板、GPU、属主修复。

## 一、当前设备状态（实证）

- 在机镜像：**v17** `out/v17/boot_r11s_v17.img` sha256 `0e43d08c0fce324f87752802dbc41d25519116254fcb9153e8fe25c96303943f`
- 内核：`7.0.14-sdm660-gcc++ #15 SMP PREEMPT`（ath10k_snoc/DRM/RMI4/音频链 全内建=y）
- DTB：v15b.dtb（R11T 全量下游集 + sofeg01-s 面板 + kpss-wdt + board-id 0x4273）
- rootfs：p69(userdata 46.34GiB) = rootfs v4 ext4（Ubuntu 24.04 + systemd + openssh + NM + 681 模块 + 110 固件 + modem 全套固件）
- 访问方式：**`sshpass -p r11s ssh r11s@10.42.0.2`**（主机侧 `enx762f486ce44f`=10.42.0.1/24，NM 连接名 r11s-ecm 已配好；USB 设备号 18d1:d005 "R11s ECM net"）
- systemctl is-system-running = **running**
- 回滚链：v15b `out/v15b/boot_r11s_v15b.img`(cfa3a8ef…) → … → `boot-debug.img`(4ff811c3…)；fastboot 是唯一刷写路径

## 二、本次已完成（全部有证据）

1. **USB 刷写链路修复**：hub 口 2-1.3 是 error -71 惯犯（fastboot D 状态卡死）→ 换 2-1.4 后 1.5s 健康刷写；30s 健康门纪律入档
2. **文档补账**：v9–v16a 断层 + 263 秒事故补入 out/test_flash_progress.md 与 STATUS.md
3. **v16a 上板验证**：r11root 链路到达内核（抗损坏对账 `r11_oot=` 实锤）
4. **v16b 复合救援 gadget**：救援 init 加 mass_storage.usb0（LUN=/dev/mmcblk1p69），失败路径单次枚举同时出 ACM 控制台 + 46.3G LUN（规避 UDC 重绑定杀 PID1）；实测三要素齐
5. **rootfs v4 部署**：dd 3.0GiB @26.7MB/s → e2fsck -fn 五遍全过
6. **重大根因实锤：ABL 随机吃 cmdline 字符**。dmesg 0.000000s 原文：`r11root=→r11_oot=`、`root=→_oot=`、`skip_initramfs→_kip_initramfs`、`init=→_nit=`；且部分启动把整个 `root=/dev/dm-0 dm=...` 追加段吞掉。这解释了历代"随机性"故障
7. **v17 修复**：init 解析模式族 `r11root=*|*11root=*|*11_oot=*` + dm-0 排除 + legacy 路径 ext4 兜底 → 刷写 → **切根成功，systemd running，SSH 通**
8. **驱动盘点（SSH 实测）**：
   - ✅ 显示：`/dev/fb0`（sofeg01-s，v14b 链路在跑）
   - ✅ 触摸：`Synaptics s3508` = event0（v14a/v14b 根治保持）
   - ✅ 声卡：`0 [R11T]: sdm660-internal` 已注册 + `OPPO R11T Headset Jack` input
   - ✅ 按键：pm8941_pwrkey / resin / gpio-keys / spmi_haptics
   - ✅ adsp、cdsp remoteproc = running；pd_mapper/fastrpc/qcom_rng 等模块自动加载
   - ✅ rootfs 固件库完整：ath10k(WCN3990 全套含 firmware-5.bin)、modem.mdt+27×bXX+mba.mbn、qca BT
9. **modem 手动拉起实验**：`echo start > /sys/class/remoteproc/remoteproc0/state`（=4080000 MSS，原本 offline）→ MBA booted → mpss loading → **crash**（SFR: "wdog or kernel error suspected"），remoteproc 自动重试中

## 三、未完成（按优先级 + 下一步精确动作）

### 1. WiFi（卡点 = modem 崩溃）
- 现状：ath10k_snoc 内建已绑定、PDR 已定位 msm/modem/wlan_pd、wlanmdsp/firmware-5.bin 齐备——**万事俱备，只欠 modem 存活**
- 下一步：SSH 后查 `systemctl status rmtfs qrtr-ns pd-mapper`（rootfs v3 时代有四件套，v4 可能没 enable）→ 没跑则 `systemctl enable --now rmtfs qrtr-ns pd-mapper`（需要 /boot/modem_fs 分区挂载给 rmtfs，见 dev-disk-by-partlabel-modemst1/2 设备已就绪）→ 再 `echo start > remoteproc0/state` 重试
- 若仍崩：查 modem 固件版本与 mba 匹配性；SFR 详读（ramdump 在 p69 可见?）
### 2. 音频实放验证
- 声卡已注册但 boot 时有 `MultiMedia1: error getting cpu dai name`（ADSP APR 链 defer）；ADSP 已 running
- 下一步：SSH `aplay -l`；用 speaker-test 破音验证；PA=tfa9890 @0x36（I²C）若无声查其供电/使能 GPIO；必要时 v18 DTB 改 adsp firmware-name="adsp.mdt"→带路径（recon/AUDIO_DTB_SURGERY_CANDIDATE_20260830.md 已写好方案）
### 3. BT
- 未动。qca 固件在 rootfs；`modprobe hci_uart` + btattach 或 serdev（DTB bluetooth 节点在）；v14a 曾实机 BT 首通（QCA setup completed）
### 4. 双面板
- v15 教训：panel@1(ams596w401) 与 panel@0(sofeg01-s) 共用 reset-gpios(TLMM53) → 需要 GPIO_SHARED_PROXY；现在**有 rootfs 可装模块**或改 =y 重编
- ABL cmdline 门控机制已实证（本机=sofeg01，会被 cmdline 选中）；方案见 recon/R11S_STATUS_DUALPANEL_GAP_20260901.md G01-G09
- 本机 ABL 已实锤下发 sofeg01_s —— 双面板意义=单镜像通吃两种量产屏
### 5. GPU
- a512_zap.mbn 无合法来源（parked）；不影响显示/card0
### 6. 杂项
- `/home/r11s` 属主坏（userns 构建）→ SSH 后 `echo r11s | sudo -S chown -R r11s:r11s /home/r11s`
- 手机无 sftp 子系统：scp 必须用 `scp -O` 或 `ssh 'cat > file' < local`
- **串口(ttyACM0)长行会被截断**：>30 字符的复合命令尾巴会丢（两次 reboot 被吃）——发短命令+标记确认
- udisks 会 automount LUN（/media/lxj/r11s-root）——dd 前先 umount

## 四、关键文件地图

| 文件 | 说明 |
|---|---|
| out/v17/ | 当前在机镜像 + ramdisk_v17 + init_v17 + README |
| out/v16b/, out/v16/, out/v15b/ | 复合 gadget 版 / v16a+rootfs v4 / 锚点 |
| rootfs/v17-ramdisk/init | 最新 init 源（抗吃字符+ext4 兜底） |
| tools/r11s_stage1_serial_watch.sh | USB/串口观察器（判定 18d1:d004/d005） |
| tools/r11s_phase4_emmc_setup.sh | ⚠ 有 UDC 冲突隐患，已被 v16b/v17 init 内建 LUN 取代 |
| recon/R11S_PANEL_FORENSICS_20260829.md / R11S_STATUS_DUALPANEL_GAP_20260901.md | 面板取证/双面板差距 |
| recon/AUDIO_DTB_SURGERY_CANDIDATE_20260830.md | 音频 DTB 修法（adsp firmware-name） |
| backups/products/products_r11s_v15b_20260902_1404/ | Image_v15 + v15b.dtb（v18 打包素材） |
| 打包命令 | tools/r11s_bootimg_pack.py --kernel Image_v15 --dtb v15b.dtb --ramdisk … --base 0x80000000 --ramdisk-offset 0x3000000 --os-version 0x12000139 --cmdline "console=ttyMSM0,115200n8 earlycon=msm_serial_dm,0xc170000 r11root=/dev/mmcblk1p69" |

## 五、已完成里程碑总账（项目全程）

- 阶段1 dtbsurg：第三方 7.0.9+手术 DTB 上板 ✓ → 阶段2 自编 7.0.14 ✓（根因=极简 DTB，见 STATUS）→ 触摸根治(v14b) ✓ → 显示点亮(v6/v13) ✓ → BT 首通(v14a) ✓ → 双面板失败定案(v15) → v15b 单面板 ✓ → v16a r11root ✓ → v16b 复合 gadget ✓ → rootfs v4 部署 ✓ → **v17 全 Linux + SSH ✓（今日）**
