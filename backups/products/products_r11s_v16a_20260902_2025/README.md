# R11s v16a 产物归档（20260902_2025）

- boot_r11s_v16a.img : v15 内核(#15) + v15b.dtb + ramdisk_v16a（r11root=/dev/mmcblk1p69）
- r11s_v16a_rootfs_v4.ext4 : Ubuntu 24.04 arm64 rootfs v4（systemd/openssh/NM/681模块/110固件；用户 r11s/r11s）
- ramdisk_v16a.cpio / v15b.dtb : 打包输入
- SHA256SUMS : 全部产物哈希
- 验证状态=未上板（主机侧构建+只读校验通过）
- 回滚链：v15b → v15 → v14b → … → boot-debug.img
