#!/bin/sh
# r11s-firstboot-fix.sh — 真机首启一次性修复（幂等，做完即标记）
#
# 背景：rootfs 在主机侧 userns chroot 构建，chown/chgrp 到系统用户被 shim
# 屏蔽（单 uid 映射内核限制），dbus/openssh-server/network-manager/polkitd
# 等包处于半配置状态。真机上 dpkg 以真 root 重跑 --configure -a 即可全部
# 修正（属主、setgid、host key、systemd 集成）。
set -e
[ -e /var/lib/r11s-firstboot-done ] && exit 0

echo "[firstboot] dpkg --configure -a (real root)"
dpkg --configure -a || true

echo "[firstboot] ssh-keygen -A"
ssh-keygen -A || true

mkdir -p /var/lib
touch /var/lib/r11s-firstboot-done
echo "[firstboot] done"
