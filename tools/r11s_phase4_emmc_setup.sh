#!/bin/busybox sh
# r11s_phase4_emmc_setup.sh — R11s 阶段 4 eMMC rootfs 施工脚本（设备侧，救援 shell 内运行）
#
# 设计依据：recon/PHASE4_ROOTFS_PLAN_20260830.md（2026-08-30，任务 28）
# 运行环境：救援 ACM shell（busybox ash；/dev/mmcblk1 已实证枚举）
#
# 安全模型：
#   - 默认 **干跑（dry-run）**：只打印将执行的命令，不写任何东西。
#   - 加 --really 才真执行；破坏性步骤（格式化/写入经 LUN 暴露）前要求输入
#     确认串 YES-WIPE-P69（--yes-i-know 可跳过，供自动化，勿轻易用）。
#   - 本脚本自身**不格式化、不 dd**：格式化与镜像写入由主机对暴露出的
#     USB mass storage LUN 完成（主机侧命令另行打印）。脚本职责 =
#     预检 → 暴露 LUN → 等主机完成 → 收回 → 只读校验。
#
# 用法：
#   sh r11s_phase4_emmc_setup.sh preflight          # 只读预检（永远安全）
#   sh r11s_phase4_emmc_setup.sh expose [--really]  # 暴露 p69 为 USB LUN
#   sh r11s_phase4_emmc_setup.sh verify [--really]  # 只读挂载抽查（建议在先跑 reclaim 后）
#   sh r11s_phase4_emmc_setup.sh reclaim [--really] # 收回 mass storage gadget
#   sh r11s_phase4_emmc_setup.sh all [--really]     # preflight+expose（verify 在主机完成后单独跑）
#
# 本轮（2026-08-30）仅交付脚本，不执行。

set -u

EMMC=/dev/mmcblk1
PART=p69
PARTDEV="$EMMC$PART"
G_ROOT=/sys/kernel/config/usb_gadget/r11s-phase4
UDC_DEV=/dev/lun0           # f_mass_storage 的 LUN 回读节点（不存在则跳过）
EXPECT_PARTNAME=userdata

log()  { echo "[phase4] $*"; }
warn() { echo "[phase4][WARN] $*" >&2; }
die()  { echo "[phase4][FATAL] $*" >&2; exit 1; }
run()  { # run <cmd...>：干跑打印，--really 才执行
    if [ "${REALLY:-0}" = 1 ]; then
        log "EXEC: $*"
        "$@" || die "命令失败（退出码 $?）：$*"
    else
        log "DRY : $*"
    fi
}

parse_args() {
    REALLY=0; FORCE_YES=0
    for a in "$@"; do
        case "$a" in
            --really)      REALLY=1 ;;
            --yes-i-know)  FORCE_YES=1 ;;
            preflight|expose|verify|reclaim|all) ACTION="$a" ;;
            *) die "未知参数：$a" ;;
        esac
    done
    [ -n "${ACTION:-}" ] || { sed -n '2,20p' "$0"; die "缺少子命令"; }
    [ "${REALLY:-0}" = 1 ] || log "干跑模式（只打印）。真执行请加 --really。"
}

# ---------- 1. 预检（只读） ----------
preflight() {
    log "== preflight 开始 =="
    [ -b "$EMMC" ] || die "$EMMC 不存在（救援态应先确认 eMMC 枚举：cat /proc/partitions）"
    [ -b "$PARTDEV" ] || die "$PARTDEV 不存在（预期 69 分区布局，见 recon 分区取证）"

    pn=$(sed -n 's/^PARTNAME=//p' "/sys/class/block/$EMMC$PART/uevent" 2>/dev/null)
    [ "$pn" = "$EXPECT_PARTNAME" ] || die "p69 PARTNAME='$pn'，预期 '$EXPECT_PARTNAME'——分区布局与取证不符，停手"
    log "OK: p69 PARTNAME=$pn"

    if grep -q "^$PARTDEV " /proc/mounts 2>/dev/null; then
        die "$PARTDEV 已挂载，先 umount"
    fi
    log "OK: $PARTDEV 未挂载"

    kb=$(sed -n "s|^ *$PARTDEV[0-9]* \([0-9]*\).*|\1|p" /proc/partitions 2>/dev/null | head -1)
    [ -n "${kb:-}" ] && log "OK: p69 大小 = $kb KB（$(awk "BEGIN{printf \"%.1f\", $kb/1048576}") GiB）" \
                     || warn "无法从 /proc/partitions 读到 p69 大小"

    # 镜像体积下限：固件部署集 83.0 MiB + userspace；分区须 >= 256 MiB
    [ -n "${kb:-}" ] && [ "$kb" -ge 262144 ] || die "p69 太小（<256 MiB），拒绝"

    # PARTUUID（供 root=PARTUUID= 备用写法；busybox 无 blkid 时从 /sys 读不到，提示主机侧取）
    log "提示：主机侧对 LUN 执行 'blkid -s PARTUUID $UDC_DEV' 可取 p69 的 GPT PARTUUID"
    log "== preflight 通过 =="
}

# ---------- 2. 暴露 p69 为 USB mass storage LUN ----------
expose() {
    log "== expose 开始 =="
    preflight
    if [ "${REALLY:-0}" = 1 ] && [ "$FORCE_YES" != 1 ]; then
        echo ""
        warn "即将把 $PARTDEV 以可读写 LUN 暴露给主机。主机侧随后的 mkfs.ext4/dd 会"
        warn "**不可逆地清空 p69（userdata）全部内容**。"
        printf "确认请输入 YES-WIPE-P69：" ; read ans
        [ "$ans" = "YES-WIPE-P69" ] || die "确认串不符，中止"
    fi

    mount -t configfs configfs /sys/kernel/config 2>/dev/null || true
    run mkdir -p "$G_ROOT/strings/0x409" "$G_ROOT/configs/c.1/strings/0x409"
    run sh -c "echo 0x18d1 > $G_ROOT/idVendor"
    run sh -c "echo 0xd004 > $G_ROOT/idProduct"
    run sh -c "echo r11s-phase4-lun > $G_ROOT/strings/0x409/serialnumber"
    run sh -c "echo OPPO > $G_ROOT/strings/0x409/manufacturer"
    run sh -c "echo 'R11s phase4 mass storage' > $G_ROOT/strings/0x409/product"
    run sh -c "echo 'phase4 LUN config' > $G_ROOT/configs/c.1/strings/0x409/configuration"
    run mkdir -p "$G_ROOT/functions/mass_storage.usb0"
    run sh -c "echo 0 > $G_ROOT/functions/mass_storage.usb0/lun.0/cdrom"
    run sh -c "echo 0 > $G_ROOT/functions/mass_storage.usb0/lun.0/ro"
    run sh -c "echo 1 > $G_ROOT/functions/mass_storage.usb0/lun.0/removable"
    run sh -c "echo $PARTDEV > $G_ROOT/functions/mass_storage.usb0/lun.0/file"
    [ "${REALLY:-0}" = 1 ] && { [ -e "$G_ROOT/configs/c.1/mass_storage.usb0" ] || \
        ln -s "$G_ROOT/functions/mass_storage.usb0" "$G_ROOT/configs/c.1/mass_storage.usb0"; } \
        || log "DRY : ln -s $G_ROOT/functions/mass_storage.usb0 $G_ROOT/configs/c.1/"
    run sh -c "set -- /sys/class/udc/*; [ -e \"\$1\" ] && echo \"\${1##*/}\" > $G_ROOT/UDC"

    log "== expose 完成（--really 时）=="
    log "---- 主机侧后续命令（在主机执行，不在本脚本内）----"
    cat <<EOF
# 0) 等 lsusb 出现 18d1:d004 且 /dev/sd? 新盘出现（记为 SD；勿认错盘！先 'lsblk -o NAME,SIZE,MODEL' 核对 46.3G）
# 1) 取 PARTUUID 备用：      blkid -s PARTUUID -o value /dev/\$SD
# 2) 格式化：                mkfs.ext4 -F -L r11s-rootfs /dev/\$SD
# 3) 写入 rootfs 镜像：      dd if=<rootfs.ext4> of=/dev/\$SD bs=4M conv=fsync status=progress
#    （镜像体积必须 <= p69；写入 512M 镜像后分区尾部留空可日后 resize2fs 扩容）
# 4) 校验：                  e2fsck -fn /dev/\$SD
# 5) 完成后回到设备救援 shell 执行： sh $0 verify --really
EOF
}

# ---------- 3. 收回 gadget（主机完成后、verify 前执行） ----------
teardown() {
    log "== reclaim：收回 mass storage gadget =="
    run sh -c "echo '' > $G_ROOT/UDC 2>/dev/null || true"
    run sh -c "rm -f $G_ROOT/configs/c.1/mass_storage.usb0 2>/dev/null || true"
    run sh -c "echo '' > $G_ROOT/functions/mass_storage.usb0/lun.0/file 2>/dev/null || true"
    run sh -c "rmdir $G_ROOT/configs/c.1/strings/0x409 $G_ROOT/configs/c.1 $G_ROOT/strings/0x409 $G_ROOT/functions/mass_storage.usb0 $G_ROOT 2>/dev/null || true"
    log "reclaim 结束（dry 时仅打印）"
}

# ---------- 4. 只读校验 ----------
verify() {
    log "== verify 开始（只读）=="
    [ -b "$PARTDEV" ] || die "$PARTDEV 不存在"
    grep -q "^$PARTDEV " /proc/mounts && die "p69 仍被挂载，先 umount 再 verify"
    MNT=/tmp/p4mnt
    run mkdir -p $MNT
    run mount -t ext4 -o ro,noatime "$PARTDEV" $MNT
    if [ "${REALLY:-0}" = 1 ]; then
        for f in /sbin/init /lib/firmware/qcom/sdm660/adsp.mdt \
                 /lib/firmware/mba.mbn /lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin \
                 /lib/firmware/qca/crbtfw21.tlv; do
            if [ -e "$MNT$f" ]; then log "OK: $f"; else warn "缺失: $f"; fi
        done
        df -h $MNT 2>/dev/null | tail -1
        log "抽查完成；如需逐文件校验，主机侧 'sha256sum -c' 对比 backups/firmware_inventory_r11s_*/SHA256SUMS"
        run umount $MNT
    else
        log "DRY : 真执行将挂载并点检 /sbin/init 与 5 个固件关键文件，然后 umount"
    fi
    log "== verify 结束 =="
}

parse_args "$@"
case "$ACTION" in
    preflight) preflight ;;
    expose)    expose ;;
    verify)    verify ;;
    reclaim)   teardown ;;
    all)       expose ;;   # preflight 已含于 expose
    *) die "不应到达" ;;
esac
exit 0
