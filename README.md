# R11s 主线 Linux 内核（r11s-mainline-kernel）

OPPO R11s（高通骁龙 660 / SDM660，arm64）主线 Linux 移植内核源树。

---

## 中文说明

### 项目简介

本仓库是让 **OPPO R11s**（Qualcomm SDM660，arm64）运行**主线 Linux** 的内核源树。
工作基于第三方适配内核 [NanShengtEAM/linux-sdm660-oppor11_s](https://github.com/NanShengtEAM/linux-sdm660-oppor11_s)
（面向 OPPO R11s 的上游适配分支）展开，当前内核版本为 **Linux 7.0.14**，在其之上进行
设备树修订、面板驱动新增与触摸（RMI4）修复。

### 当前状态

- **启动**：实机启动稳定，连续存活超过 60 秒；
- **显示**：已点亮，面板为三星 **SOFEG01_S**（1080×2160 命令模式 AMOLED）；
- **触摸**：调试中（Synaptics s3508，RMI4 over I2C，详见 Releases 各阶段说明）；
- **救援通道**：USB ACM gadget（USB ID `18d1:d004`），启动后可经 `ttyGS0` 获得救援 shell，
  用于无串口条件下的日志取证与调试。

### 仓库内容

- 主线内核源树（Linux 7.0.14，基于上述第三方适配内核修订）；
- 设备树：`arch/arm64/boot/dts/qcom/sdm660-oppo-r11s.dts`（含看门狗、面板、触摸节点）；
- 面板驱动：`drivers/gpu/drm/panel/panel-samsung-sofeg01-s.c`（compatible `samsung,sofeg01-s`，
  初始化序列转录自原厂内核源码）；
- 触摸修复：`drivers/input/rmi4/` 下 PDT 扫描容错（重复/未知函数号跳过）与
  I2C 传输重试（对齐原厂驱动的重试策略）；
- 构建配置：`arch/arm64/configs/r11s_defconfig`。

### 快速上手

交叉编译（aarch64 工具链）：

```bash
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=build/r11s_phase2 r11s_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=build/r11s_phase2 -j$(nproc) Image.gz dtbs
```

注意事项：

- **体积门限**：解压后的内核映像必须 ≤ `0x3000000`（50,331,648 字节），
  否则引导阶段无法装载；构建后请核对 `Image` 解压尺寸。
- **刷写**：设备需已解锁 bootloader，进入 fastboot 后：
  ```bash
  fastboot flash boot boot.img
  ```
- **回滚**：刷写前请自行留存一份可正常启动的原厂 `boot.img`；出现异常时用
  `fastboot flash boot <原厂 boot.img>` 恢复。本仓库不提供原厂镜像。

### Releases

各阶段的可刷写 boot 镜像发布在本仓库的 [Releases](https://github.com/lxjuyn/r11s-mainline-kernel/releases) 页面，
按阶段（stage1 / stage2 / stage3 / stage5）打 tag。每个 release 附带：

- 相对上一版的变更说明；
- 实机刷写验证结论；
- 回滚方法；
- 镜像及 `SHA256SUMS` 校验文件。

### 致谢

- [NanShengtEAM/linux-sdm660-oppor11_s](https://github.com/NanShengtEAM/linux-sdm660-oppor11_s)：
  本项目赖以起步的 R11s 主线适配内核；
- OPPO 公开的内核源码（设备树参数与面板初始化序列的事实来源）。

### 许可

本仓库沿用内核源树许可：**GPL-2.0**（见 [COPYING](COPYING)）。

---

## English

### Introduction

This repository contains the mainline Linux kernel source tree used to bring
**mainline Linux** up on the **OPPO R11s** (Qualcomm SDM660, arm64).
The work is based on the third-party port
[NanShengtEAM/linux-sdm660-oppor11_s](https://github.com/NanShengtEAM/linux-sdm660-oppor11_s)
(an upstream-oriented port for the OPPO R11s). The current kernel version is
**Linux 7.0.14**, on top of which we apply device-tree revisions, a new panel
driver and RMI4 touchscreen fixes.

### Current status

- **Boot**: boots reliably on real hardware and stays alive well beyond 60 seconds;
- **Display**: working — Samsung **SOFEG01_S** panel (1080×2160 command-mode AMOLED);
- **Touchscreen**: under active debugging (Synaptics s3508, RMI4 over I2C;
  see the per-stage release notes);
- **Rescue channel**: USB ACM gadget (USB ID `18d1:d004`); after boot a rescue
  shell is available on `ttyGS0`, used for log capture and debugging without a
  serial console.

### Repository contents

- Mainline kernel source tree (Linux 7.0.14, revised from the third-party port
  mentioned above);
- Device tree: `arch/arm64/boot/dts/qcom/sdm660-oppo-r11s.dts` (watchdog,
  panel and touchscreen nodes);
- Panel driver: `drivers/gpu/drm/panel/panel-samsung-sofeg01-s.c`
  (compatible `samsung,sofeg01-s`; the init sequence is transcribed from the
  vendor kernel sources);
- Touch fixes under `drivers/input/rmi4/`: PDT scan tolerance (skip
  duplicate/unknown function entries) and I2C transfer retry (aligned with the
  vendor driver's retry policy);
- Build configuration: `arch/arm64/configs/r11s_defconfig`.

### Getting started

Cross-compilation (aarch64 toolchain):

```bash
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=build/r11s_phase2 r11s_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=build/r11s_phase2 -j$(nproc) Image.gz dtbs
```

Notes:

- **Size gate**: the decompressed kernel image must be ≤ `0x3000000`
  (50,331,648 bytes), otherwise the bootloader cannot load it. Check the
  decompressed `Image` size after each build.
- **Flashing**: the device must have an unlocked bootloader; in fastboot mode:
  ```bash
  fastboot flash boot boot.img
  ```
- **Rollback**: keep your own known-good stock `boot.img` before flashing; if
  anything goes wrong, restore it with `fastboot flash boot <stock boot.img>`.
  No stock images are distributed in this repository.

### Releases

Flashable boot images for each development stage are published under
[Releases](https://github.com/lxjuyn/r11s-mainline-kernel/releases), tagged by
stage (stage1 / stage2 / stage3 / stage5). Each release includes:

- changes relative to the previous image;
- on-device verification results;
- rollback instructions;
- the image and a `SHA256SUMS` checksum file.

### Acknowledgements

- [NanShengtEAM/linux-sdm660-oppor11_s](https://github.com/NanShengtEAM/linux-sdm660-oppor11_s):
  the R11s mainline port this project started from;
- OPPO's published kernel sources (the factual source for device-tree
  parameters and the panel init sequence).

### License

This repository follows the kernel source tree license: **GPL-2.0**
(see [COPYING](COPYING)).
