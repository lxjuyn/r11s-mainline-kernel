# U-Boot 工具链基线 — 取证记录

> Timestamp: 2026-08-09 22:5x
> 来源: workflow w3sjyuret (1 sonnet agent, 45k tokens)。主机侧验证, 无设备。

## 结论

- 树: `/home/<user>/claude/r11/build/u-boot` (shallow, depth 1), **2026.10-rc1** @ d0615e4a (master)
- mkimage: **works** (version 2026.10-rc1), via `make tools-only_defconfig && make tools`
- aarch64 工具链: **PASS** (aarch64-linux-gnu-gcc 13.3, 468 arm64 CC/AS, 602 个 .o)

## 关键架构发现 (对 SDM660 移植决定性)

1. **无 CONFIG_ARCH_QCOM**: 新版 U-Boot 用 `CONFIG_ARCH_SNAPDRAGON=y`。
2. **无 Qualcomm 板级 CONFIG_TARGET_***: Qualcomm 目标是**通用**的 (arch/arm/mach-snapdragon/board.c),
   SYS_CONFIG_NAME="qcom", 板卡完全由 `CONFIG_DEFAULT_DEVICE_TREE` 选择。
3. **SDM660 移植路径** (现成模式): 在 `dts/upstream/src/arm64/qcom/` 加 `sdm660` DTS,
   设 `CONFIG_DEFAULT_DEVICE_TREE`, 使能 SDM660 clock 驱动。参考: sdm845-db845c
   (board/qualcomm/dragonboard845c, 含 db845c.its)。
4. **`file u-boot.bin` -> "Linux kernel ARM64 boot executable Image"**: Qualcomm U-Boot
   被构建成 ARM64 Image 格式用于链载 —— 与 R11s ABL 期望加载的 arm64 Image 契约吻合。
   (对 "U-Boot 作 fake kernel 进 boot.img" 入口极其有利; 具体契约待 wbrjd8dk7 设计定案)

## 产物

- u-boot.bin = 1,535,824 B (~1.46 MiB)
- u-boot-nodtb.bin = 1,417,792 B
- u-boot.dtb = 118,032 B
- 当前 in-tree .config = qcom_defconfig + `CONFIG_TOOLS_MKEFICAPSULE=n`
- 树大小 571M

## 可复现性注意

- 无 root (sudo 需密码): swig 4.2.1 从源码装到 `~/.local/bin` (必须 PATH), 否则 make tools 失败;
  gnutls 头缺失 -> 必须禁用 CONFIG_TOOLS_MKEFICAPSULE。
- 若从零重建: 需要 swig + 禁用 mkeficapsule。
