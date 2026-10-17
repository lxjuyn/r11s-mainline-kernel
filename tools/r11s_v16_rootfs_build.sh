#!/bin/bash
# r11s_v16_rootfs_build.sh — R11s v16a Ubuntu rootfs v4 主机侧构建（免 sudo，userns 方案）
#
# 输入：out/ubuntu-base-24.04.3-base-arm64.tar.gz（SHA256 校验）
#       build/r11s_phase2（v15b 同版内核构建树，modules_install 来源）
#       out/r11s_phase4a_rootfs_v3.ext4（/lib/firmware 固件集提取来源）
# 输出：out/v16/r11s_v16a_rootfs_v4.ext4 + SHA256SUMS + build.log
#
# 设计：全部阶段幂等可重入；慢阶段（apt）打时间戳日志；默认安全（不碰设备）。
# 用法：tools/r11s_v16_rootfs_build.sh <prep|extract|apt|modules|firmware|pack|sums|all>

set -euo pipefail

WS=/home/<user>/claude/r11
KTREE=$WS/out/linux-sdm660-oppor11-t-qcom-sdm660-7.0.y
KBUILD=$WS/build/r11s_phase2
KREL=7.0.14-sdm660-gcc++
BASE_TAR=$WS/out/ubuntu-base-24.04.3-base-arm64.tar.gz
BASE_SUM=$WS/out/ubuntu-base-24.04.3-base-arm64.SHA256SUM
V3_IMG=$WS/out/r11s_phase4a_rootfs_v3.ext4
BUILD=$WS/rootfs/v16a-build
ROOTFS=$BUILD/rootfs
OVERLAY=$WS/rootfs/v16a-overlay
OUTD=$WS/out/v16
IMG=$OUTD/r11s_v16a_rootfs_v4.ext4
IMG_SIZE=3072M
# --no-install-recommends 最小包集：systemd/ssh/网络/基础工具
PKGS="systemd-sysv udev kmod dbus openssh-server network-manager wpasupplicant \
      sudo iproute2 iputils-ping less ca-certificates rfkill usbutils vim-tiny"

log() { echo "[v16build $(date +%H:%M:%S)] $*"; }
die() { echo "[v16build][FATAL] $*" >&2; exit 1; }

stage_prep() {
    mkdir -p "$BUILD" "$ROOTFS" "$OUTD"
    log "校验 ubuntu-base SHA256"
    local expect actual
    expect=$(awk '{print $1}' "$BASE_SUM")
    actual=$(sha256sum "$BASE_TAR" | awk '{print $1}')
    [ "$expect" = "$actual" ] || die "ubuntu-base sha256 不符: $actual != $expect"
    log "sha256 OK: $actual"
    [ -f "$KBUILD/include/config/kernel.release" ] || die "内核构建树缺失: $KBUILD"
    local rel; rel=$(cat "$KBUILD/include/config/kernel.release")
    [ "$rel" = "$KREL" ] || die "kernel.release 不符: $rel != $KREL"
    log "内核构建树 OK ($KREL)"
}

stage_extract() {
    log "解包 ubuntu-base -> $ROOTFS"
    /usr/bin/rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"
    tar xzf "$BASE_TAR" -C "$ROOTFS"
    cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/"
    cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
    log "解包完成: $(du -sh "$ROOTFS" | cut -f1)"
}

# 在 unshare -rm 内完成挂载准备 + chroot + 清理（免 sudo fake-root）。
# 注意：userns 里 mount --bind /dev 整目录（devtmpfs）和新挂 proc/sys 都会被
# 内核拒绝；采用 rootless 容器标准做法：tmpfs /dev + 逐个 bind 关键节点，
# /proc /sys 用 bind 挂载。
# 用法: in_ns_chroot '<chroot 内 bash 命令串（不得含单引号）>'
in_ns_chroot() {
    unshare -rm bash -s "$ROOTFS" "$1" <<'NSEOF'
set -e
ROOTFS=$1; INNER=$2
mount --bind /proc "$ROOTFS/proc" || echo "[warn] /proc bind 失败（apt 可继续）"
mount --bind /sys "$ROOTFS/sys"   || echo "[warn] /sys bind 失败（apt 可继续）"
# /dev：userns 内打开外部 devtmpfs 的设备节点必 EACCES、mknod 也 EPERM；
# 用 tmpfs + 空普通文件占位（shell 重定向 >/dev/null 当普通文件用即可），
# pty 走 userns 自有的新 devpts 实例。
mount -t tmpfs tmpfs "$ROOTFS/dev"
for f in null zero full random urandom tty; do touch "$ROOTFS/dev/$f"; done
mkdir -p "$ROOTFS/dev/pts" "$ROOTFS/dev/shm"
mount -t devpts -o newinstance,ptmxmode=666 devpts "$ROOTFS/dev/pts" 2>/dev/null || true
ln -sf pts/ptmx "$ROOTFS/dev/ptmx"
mount -t tmpfs tmpfs "$ROOTFS/dev/shm" 2>/dev/null || true
chroot "$ROOTFS" /usr/bin/qemu-aarch64-static /bin/bash -c "$INNER"
umount "$ROOTFS/dev/shm" 2>/dev/null || true
umount "$ROOTFS/dev/pts" 2>/dev/null || true
umount "$ROOTFS/sys" "$ROOTFS/proc" 2>/dev/null || true
umount -R "$ROOTFS/dev" 2>/dev/null || true
NSEOF
}

stage_apt() {
    command -v unshare >/dev/null || die "unshare 缺失"
    log "chroot apt 安装包集（qemu-aarch64，慢阶段）: $PKGS"
    # policy-rc.d 阻止 postinst 起服务
    mkdir -p "$ROOTFS/usr/sbin"
    printf '#!/bin/sh\nexit 101\n' > "$ROOTFS/usr/sbin/policy-rc.d"
    chmod +x "$ROOTFS/usr/sbin/policy-rc.d"
    # userns 单 uid 映射下 apt 沙箱用户(_apt) setuid 必失败 → Sandbox::User=root
    printf 'APT::Sandbox::User "root";\n' > "$ROOTFS/etc/apt/apt.conf.d/99rootless"
    # chown/chgrp/dpkg-statoverride 到非映射 uid/gid 必 EINVAL。dpkg 会为
    # maintainer scripts 重置 PATH，PATH shim 无效 → 二进制级容错包装
    # （真执行、屏蔽错误；属主偏差由真机首启 firstboot-fix 修正）。打包前还原。
    wrap_bins() {
        local b
        for b in chown chgrp dpkg-statoverride; do
            [ -f "$ROOTFS/usr/bin/$b.real" ] || /usr/bin/mv "$ROOTFS/usr/bin/$b" "$ROOTFS/usr/bin/$b.real"
            printf '#!/bin/sh\n/usr/bin/%s.real "$@" 2>/dev/null\nexit 0\n' "$b" > "$ROOTFS/usr/bin/$b"
            chmod +x "$ROOTFS/usr/bin/$b"
        done
    }
    unwrap_bins() {
        local b
        for b in chown chgrp dpkg-statoverride; do
            [ -f "$ROOTFS/usr/bin/$b.real" ] && /usr/bin/mv -f "$ROOTFS/usr/bin/$b.real" "$ROOTFS/usr/bin/$b"
        done
    }
    wrap_bins
    in_ns_chroot "
        export DEBIAN_FRONTEND=noninteractive PATH=/usr/sbin:/usr/bin:/sbin:/bin
        apt-get update
        apt-get install -y --no-install-recommends $PKGS || true
        dpkg --configure -a || true
        echo '--- 未完全配置包清单（应为空或非关键）---'
        dpkg -l 2>/dev/null | grep -vE '^ii |^Desired|^\| |^\+' || true
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    "
    unwrap_bins
    /usr/bin/rm -f "$ROOTFS/etc/apt/apt.conf.d/99rootless"
    /usr/bin/rm -f "$ROOTFS/usr/sbin/policy-rc.d"
    [ -x "$ROOTFS/usr/lib/systemd/systemd" ] || die "systemd 未装上"
    log "apt 完成；systemd 在位（残余属主偏差由 firstboot-fix 真机修正）"
}

stage_overlay() {
    log "叠加 rootfs/v16a-overlay 配置"
    [ -d "$OVERLAY" ] || die "overlay 目录缺失: $OVERLAY"
    rsync -a "$OVERLAY/" "$ROOTFS/"
    # 用户与基础配置（chroot 内）
    in_ns_chroot "
        set -e
        export PATH=/usr/sbin:/usr/bin:/sbin:/bin
        echo r11s > /etc/hostname
        grep -q r11s /etc/hosts || echo \"127.0.1.1 r11s\" >> /etc/hosts
        id r11s 2>/dev/null || useradd -m -s /bin/bash r11s
        echo \"r11s:r11s\" | chpasswd
        usermod -aG sudo r11s
        passwd -l root || true
        systemctl enable ssh.service NetworkManager.service r11s-usb-ecm.service r11s-firstboot-fix.service
        systemctl mask apt-daily.timer apt-daily-upgrade.timer || true
    "
    log "overlay 完成（用户 r11s/r11s，ssh+NM+usb-ecm 已 enable）"
}

stage_modules() {
    log "modules_install ($KREL) -> rootfs"
    make -C "$KTREE" O="$KBUILD" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        modules_install INSTALL_MOD_PATH="$ROOTFS" INSTALL_MOD_STRIP=1 2>&1 | tail -3
    local n
    n=$(find "$ROOTFS/lib/modules/$KREL" -name "*.ko*" 2>/dev/null | wc -l)
    [ "$n" -gt 100 ] || die "模块数异常: $n"
    [ -f "$ROOTFS/lib/modules/$KREL/modules.dep" ] || die "modules.dep 缺失（depmod 未跑）"
    log "模块 $n 个，depmod 产物在位"
}

stage_firmware() {
    log "从 v3 提取 /lib/firmware"
    /usr/bin/rm -rf "$BUILD/fwdump"; mkdir -p "$BUILD/fwdump"
    debugfs -R "rdump /lib/firmware $BUILD/fwdump" "$V3_IMG" >/dev/null 2>&1
    local src="$BUILD/fwdump"
    [ -d "$src/firmware" ] && src="$src/firmware"   # rdump 可能多包一层
    mkdir -p "$ROOTFS/lib/firmware"
    rsync -a "$src/" "$ROOTFS/lib/firmware/"
    local n; n=$(find "$ROOTFS/lib/firmware" -type f | wc -l)
    [ "$n" -gt 50 ] || die "固件数异常: $n"
    [ -d "$ROOTFS/lib/firmware/ath10k/WCN3990" ] || die "ath10k/WCN3990 缺失"
    log "固件 $n 个文件（含 ath10k/WCN3990）"
}

stage_pack() {
    log "打 ext4 镜像 ($IMG_SIZE, unshare fake-root 保持 root 属主)"
    # 清掉构建期 /dev 占位文件与 shim（真机 devtmpfs 覆盖 /dev，此为整洁）；
    # 容错包装若因中断未还原，这里兜底还原真实二进制（镜像必须带原版）
    find "$ROOTFS/dev" -mindepth 1 -maxdepth 1 -exec /usr/bin/rm -rf {} + 2>/dev/null || true
    /usr/bin/rm -rf "$ROOTFS/build-shim"
    local b
    for b in chown chgrp dpkg-statoverride; do
        [ -f "$ROOTFS/usr/bin/$b.real" ] && /usr/bin/mv -f "$ROOTFS/usr/bin/$b.real" "$ROOTFS/usr/bin/$b"
    done
    /usr/bin/rm -f "$IMG"
    unshare -rm /usr/sbin/mkfs.ext4 -q -d "$ROOTFS" -L r11s-root "$IMG" "$IMG_SIZE"
    log "镜像: $(du -h "$IMG" | cut -f1) -> $IMG"
    # 只读 sanity
    debugfs -R "stat /usr/lib/systemd/systemd" "$IMG" 2>/dev/null | grep -q "Type: regular" \
        || die "镜像内 systemd 校验失败"
    debugfs -R "ls /lib/modules" "$IMG" 2>/dev/null | grep -q "$KREL" \
        || die "镜像内 modules 校验失败"
    log "镜像只读校验 PASS"
}

stage_sums() {
    (cd "$OUTD" && sha256sum "$(basename "$IMG")" > SHA256SUMS)
    log "SHA256SUMS: $(cat "$OUTD/SHA256SUMS")"
    log "rootfs 内容量: $(du -sh "$ROOTFS" | cut -f1)"
}

main() {
    local stage="${1:-all}"
    case "$stage" in
        prep) stage_prep ;;
        extract) stage_prep; stage_extract ;;
        apt) stage_apt ;;
        overlay) stage_overlay ;;
        modules) stage_modules ;;
        firmware) stage_firmware ;;
        pack) stage_pack ;;
        sums) stage_sums ;;
        all) stage_prep; stage_extract; stage_apt; stage_overlay; stage_modules; stage_firmware; stage_pack; stage_sums ;;
        *) die "未知阶段: $stage" ;;
    esac
    log "阶段 [$stage] 完成"
}
main "$@"
