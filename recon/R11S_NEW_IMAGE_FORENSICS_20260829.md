# boot-r11s-NEW.img 取证报告（2026-08-29）

来源：用户提供（/home/<user>/claude/r11/boot-r11s-NEW.img，sha256 1e479b79…27fa648）。

## 已证实
- 内核：`Linux version 7.0.14-sdm660+ (Nan5heng@Homo) (aarch64-linux-gnu-gcc (GCC) 16.1.0)`——上游作者（NanShengtEAM，构建机名 Nan5heng）的新构建；解压 28,704,768 B；IKCONFIG 完整提取 8100 行
- DTB：原生 R11s 版（board-id 0x4273、model "OPPO R11s"、compatible "oppo,r11s qcom,sdm660"），480 节点全量下游集
  - rmi4 触摸节点：`touchscreen@20`（syna,rmi4-i2c，F01+F12，vdd/vio 供电，reset-gpios=<tlmm 66>，interrupts=<tlmm 67>）——与原厂 r11s..dts:11952 的 synaptics 路线吻合
  - wcn3990 WiFi + wcn3990 BT 节点在位
  - **无任何 watchdog 节点**（wdt/watchdog 全文零命中）——与初代第三方镜像同缺陷
  - 面板节点仅 `samsung,s6e3fa3`（一处，line ~2296 反编译行号）
- config 关键：QCOM_WDT=m、RMI4_CORE=m/I2C=m/F12=y、DRM_MSM=m、ATH10K_SNOC=m、BT_QCA=m、MODULE_COMPRESS=y、LOCALVERSION="-sdm660"
- ramdisk：gzip cpio，init 契约与初代完全一致（PARTNAME=userdata → btrfs subvol=@，失败进 0x18d1:0xd004 救援 shell，产品串改为 "R11s root mount failure"）；**不含任何 .ko 模块**
- 手术重打包：boot_r11s_NEW_wdtsurg.img（0ca184e4…）= 作者内核 gz + 作者 DTB + watchdog@17817000（kpss-wdt，sleep_clk=0x24，恰与手术模板同 phandle）+ 作者 ramdisk；与原镜像唯一差异 kernel_size +116B；dtc 往返字节级保真自检通过

## 未证实 / 风险
- 作者面板只配 s6e3fa3（R11T 面板）；我们实机 ABL 实测下发 `qcom,mdss_dsi_oppo17011samsung_sofeg01_s_1080p_cmd` → 依取证判断作者镜像显示不会点亮（待上机证实）
- 作者内核 vermagic 7.0.14-sdm660+ SMP preempt mod_unload aarch64：如需为其配模块，可用上游参考仓库源码（edf5e0d）+ 提取 config 本地构建（MODVERSIONS 未开，需同 vermagic）
- 60s 启动窗口 WDT：作者镜像未手术版风险未知（我们的 reboot-from-fastboot 路径未触发过咬死；冷启动未测）——故先刷手术版

## 给阶段的建议
1. 先刷 wdtsurg 手术版（单变量 +watchdog），判定作者集成在我们板上的真实水平（触摸/WiFi 节点在 DTB 层已就位，但需模块才能工作；先看救援 shell 与 dmesg）
2. 我们 v2 基线（自编内核+手术 DTB）与作者镜像并存：触摸/WiFi 移植可直接借用作者 DTB 的节点参数（i2c 总线/地址/GPIO 与我们原厂取证一致）
3. 显示阶段继续以 SOFEG01_S 为准；s6e3fa3 仅作作者设备的旁证
