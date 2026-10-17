# v17 — 抗 ABL 吃字符版（r11root 模式族 + legacy ext4 兜底）

## 根因（本次上机实锤）
ABL 拼接 cmdline 随机吃字符：dmesg 0.000000s 实证内核收到 `r11_oot=/dev/mmcblk1p69`
（r11root 第 4 字符被吃；同型已见 root=→_oot=、skip_initramfs→_kip_initramfs、init=→_nit=）。
v16a/v16b init 的精确匹配 `r11root=*` 随机失灵 → legacy 路径 → btrfs 挂 ext4 失败 → 秒进救援。

## v17 init 相对 v16b 的改动（唯一变量；kernel #15/DTB/复合 gadget 不动）
1. r11root 解析模式族：r11root=* | *11root=* | *11_oot=* → ${w#*=}
2. root= 回退解析到 /dev/dm-* 时放弃（ABL 的 verity 占位根不可用）
3. legacy 路径：btrfs subvol=@ 失败后自动试 ext4（userdata=dev 机的 rootfs 场景），双失败才落救援

## 产物
- boot_r11s_v17.img / ramdisk_v17.cpio / init_v17
