# v16a ramdisk 来源说明

本目录 = `out/v15/ramdisk_v15.cpio`（v15 救援 ramdisk，未压缩 newc，含 adsp/cdsp/ath10k/BT/a530 固件）的解包副本，唯一改动是 `init` 的 `r11root=` 补丁（git 仅跟踪本 README 与 init，固件等二进制不入库）。

## r11root= 补丁动机

ABL 启动时会在 boot.img cmdline 之后追加自己的 `root=/dev/dm-0`（实测 v15b /proc/cmdline）。v10 init 的解析循环是“最后出现的 root= 生效”，因此打包器 `--root` 注入的值必被覆盖 → 永远等 dm-0 → 落救援 shell（v15b 现状）。

补丁让 `r11root=` 拥有最高优先级；缺省时行为与 v10 逐字节一致，所有失败路径（块设备未出现/挂载失败/无 sbin/init）仍落回救援 ACM shell，防砖红线不动。

## 打包

```
cd rootfs/v16a-ramdisk
find . -print0 | cpio --null -o -H newc -R 0:0 --quiet > out/v16/ramdisk_v16a.cpio
```

boot 镜像（v16a-flash-pivot 阶段）：
`python3 tools/r11s_bootimg_pack.py --kernel out/v15/Image --dtb out/v16/v15b.dtb --ramdisk out/v16/ramdisk_v16a.cpio --cmdline "console=ttyMSM0,115200n8 earlycon=msm_serial_dm,0xc170000 r11root=/dev/mmcblk1p69" --out out/v16/boot_r11s_v16a.img`
