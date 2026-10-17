#!/bin/sh
# r11s_onboard_check.sh — OPPO R11s mainline 上板验收一键脚本
#
# 设计约束：
#  - 目标环境 = 救援 shell（busybox ash，无 bash），也可直接经 ACM 逐条粘贴
#  - 纯只读：只读 /sys /proc /dev 与 dmesg，不写任何文件、不改任何状态
#  - 每段给出 PASS / FAIL / EXPECTED 判定；退出码恒为 0（结论看文本）
#  - 主机冒烟：缺设备节点时应优雅输出 FAIL，而不是报错退出
#
# 用法：sh r11s_onboard_check.sh

LC_ALL=C
export LC_ALL

PASS_N=0
FAIL_N=0
EXP_N=0

say()  { printf '%s\n' "$*"; }
hdr()  { say ""; say "==== [$1] $2 ===="; }
vpass() { PASS_N=$((PASS_N+1)); say "  -> [$1] PASS"; }
vfail() { FAIL_N=$((FAIL_N+1)); say "  -> [$1] FAIL"; }
vexp()  { EXP_N=$((EXP_N+1)); say "  -> [$1] EXPECTED"; }

# dmesg 兜底（救援 shell 可能无 dmesg 或权限受限）
klog() {
    if command -v dmesg >/dev/null 2>&1; then
        dmesg 2>/dev/null
    elif [ -r /dev/kmsg ]; then
        cat /dev/kmsg 2>/dev/null | sed 's/^[0-9]*,[0-9]*,[0-9]*[,;-]*//' 2>/dev/null
    fi
}

say "R11s onboard check @ $(date 2>/dev/null || echo 'no date cmd')"
say "kernel: $(cat /proc/version 2>/dev/null || echo unknown)"

# ---------------------------------------------------------------- 1. 触摸
hdr TOUCH "触摸（rmi4 / input 子系统）"

EV_N=0
for ev in /dev/input/event*; do
    [ -e "$ev" ] || continue
    EV_N=$((EV_N+1))
    say "  event node: $ev"
done
if [ "$EV_N" -eq 0 ]; then
    say "  /dev/input/event* 不存在"
    vfail TOUCH "无 input event 节点"
    MT_CHECKED=0
else
    # 从 sysfs 枚举能力（比 EVIOCG* 更适合无工具环境）
    MT_CHECKED=0
    for d in /sys/class/input/event*; do
        [ -d "$d" ] || continue
        dev=${d##*/}
        absf="$d/device/capabilities/abs"
        evf="$d/device/capabilities/ev"
        [ -r "$evf" ] || continue
        ev=$(cat "$evf" 2>/dev/null)
        abs=$(cat "$absf" 2>/dev/null)
        name=$(cat "$d/device/name" 2>/dev/null || echo '?')
        say "  $dev name='$name' ev=$ev abs=$abs"
        # ABS 位图长度 > 8 位十六进制 => 含 ABS_MT_*（>0x1f 的位）
        if [ -n "$abs" ] && [ "${#abs}" -gt 8 ]; then
            say "  $dev: ABS_MT_* 位存在（多点触控能力）"
            MT_CHECKED=1
        elif [ -n "$abs" ] && [ "$abs" != "0" ]; then
            say "  $dev: 仅基础 ABS 轴"
            MT_CHECKED=1
        fi
    done
    if [ "$MT_CHECKED" -eq 1 ]; then
        vpass TOUCH "input 节点枚举 + ABS 能力检查完成"
    else
        vfail TOUCH "有 event 节点但读不到能力位图"
    fi
    # rmi4 中断行
    if [ -r /proc/interrupts ]; then
        irq=$(grep -i -E 'rmi4|synaptics' /proc/interrupts 2>/dev/null)
        if [ -n "$irq" ]; then
            say "  /proc/interrupts rmi4 行:"
            say "$irq" | sed 's/^/    /'
        else
            say "  /proc/interrupts 无 rmi4/synaptics 行（触摸中断未触发或驱动名不同）"
        fi
    fi
fi

# ---------------------------------------------------------------- 2. 显示
hdr DISPLAY "显示（fb0 / 面板）"

if [ -d /sys/class/graphics/fb0 ]; then
    vs=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || echo '?')
    mode=$(cat /sys/class/graphics/fb0/mode 2>/dev/null || echo '?')
    name=$(cat /sys/class/graphics/fb0/name 2>/dev/null || echo '?')
    say "  fb0 name=$name virtual_size=$vs mode=$mode"
    if [ "$vs" != "?" ] && [ "$vs" != "0,0" ]; then
        vpass DISPLAY "fb0 存在且有有效分辨率"
    else
        vfail DISPLAY "fb0 存在但分辨率无效"
    fi
else
    say "  /sys/class/graphics/fb0 不存在"
    vfail DISPLAY "无 fb0"
fi
pl=$(klog | grep -i -E 'panel|sofeg|ams596|drm|dpu|mdss|dsi' | tail -n 12)
if [ -n "$pl" ]; then
    say "  dmesg 面板/显示相关行(尾12):"
    say "$pl" | sed 's/^/    /'
else
    say "  dmesg 无面板/显示相关行（可能 DRM 仅走 fbdev 或日志被截）"
fi

# ---------------------------------------------------------------- 3. 电池/充电
hdr POWER "电池/充电（power_supply）"

PS_N=0
for ps in /sys/class/power_supply/*; do
    [ -d "$ps" ] || continue
    PS_N=$((PS_N+1))
    n=${ps##*/}
    t=$(cat "$ps/type" 2>/dev/null || echo '?')
    st=$(cat "$ps/status" 2>/dev/null || echo '-')
    cap=$(cat "$ps/capacity" 2>/dev/null || echo '-')
    v=$(cat "$ps/voltage_now" 2>/dev/null || echo '-')
    i=$(cat "$ps/current_now" 2>/dev/null || echo '-')
    say "  $n: type=$t status=$st capacity=$cap voltage_now=$v current_now=$i"
done
if [ "$PS_N" -eq 0 ]; then
    say "  /sys/class/power_supply 为空或不存在"
    vfail POWER "无 power_supply 节点"
else
    vpass POWER "power_supply 枚举完成（见上数值）"
fi
chg=$(klog | grep -i -E 'smb|charger|pm660|fg_|fuel' | tail -n 8)
[ -n "$chg" ] && { say "  dmesg 充电相关行(尾8):"; say "$chg" | sed 's/^/    /'; }

# ---------------------------------------------------------------- 4. 音频
hdr AUDIO "音频（ALSA 声卡 / q6 链）"

if [ -r /proc/asound/cards ] && [ -s /proc/asound/cards ]; then
    say "  /proc/asound/cards:"
    cat /proc/asound/cards | sed 's/^/    /'
    if grep -q -i -E 'sdm660|oppo|r11' /proc/asound/cards 2>/dev/null; then
        vpass AUDIO "声卡已注册"
    else
        vpass AUDIO "有声卡（非 sdm660 机驱动，见上行）"
    fi
    if [ -r /proc/asound/pcms ]; then
        say "  /proc/asound/pcms:"
        cat /proc/asound/pcms | sed 's/^/    /'
    fi
else
    say "  /proc/asound/cards 缺失或为空"
    ad=$(klog | grep -i -E 'asoc|q6|apr|glink|ak4376|tfa989|sdm660-internal|snd_soc|defer' | tail -n 20)
    if [ -n "$ad" ]; then
        say "  dmesg 音频相关行(尾20):"
        say "$ad" | sed 's/^/    /'
    fi
    if klog | grep -q -i -E 'defer|deferred'; then
        vexp AUDIO "无声卡但见 probe defer（组件等待中，符合预期内失败）"
    elif klog | grep -q -i -E 'failed to load firmware|firmware.*not found|mdt'; then
        vexp AUDIO "无声卡，疑似固件加载失败（对照 AUDIO_DTB_SURGERY 卡点A）"
    else
        vfail AUDIO "无声卡且无相关日志（模块可能未加载）"
    fi
    if command -v lsmod >/dev/null 2>&1; then
        am=$(lsmod 2>/dev/null | grep -c -i -E 'snd|q6|apr|asoc')
        say "  lsmod 音频相关模块数: $am"
    fi
fi

# ---------------------------------------------------------------- 5. 无线
hdr WIRELESS "无线（remoteproc / ath10k / 蓝牙 / QMI）"

RP_N=0
for rp in /sys/class/remoteproc/remoteproc*; do
    [ -d "$rp" ] || continue
    RP_N=$((RP_N+1))
    nm=$(cat "$rp/name" 2>/dev/null || echo '?')
    st=$(cat "$rp/state" 2>/dev/null || echo '?')
    say "  ${rp##*/}: name=$nm state=$st"
done
[ "$RP_N" -eq 0 ] && say "  无 remoteproc 节点（对应模块未加载属常见，见 EXPECTED）"

wl=$(klog | grep -i -E 'ath10k|hci|qca|qmi|wcn|bluetooth|wifi' | tail -n 20)
[ -n "$wl" ] && { say "  dmesg 无线相关行(尾20):"; say "$wl" | sed 's/^/    /'; }

if klog | grep -q -i -E 'failed to load.*firmware|Direct firmware load.*failed|firmware: failed'; then
    vexp WIRELESS "见缺固件日志——缺固件=预期（固件在 rootfs /lib/firmware，确认部署后重验）"
elif [ "$RP_N" -gt 0 ]; then
    vpass WIRELESS "remoteproc 节点在位（见上 state）"
else
    vexp WIRELESS "无 remoteproc 节点且无缺固件日志——模块未加载（预期内，待 modprobe）"
fi

# ---------------------------------------------------------------- 6. 稳定性
hdr STABILITY "稳定性（uptime / panic / oops）"

up=$(cat /proc/uptime 2>/dev/null || echo '?')
say "  uptime(秒): ${up%% *}"
la=$(cat /proc/loadavg 2>/dev/null || echo '?')
say "  loadavg: $la"

bad=$(klog | grep -i -E 'panic|oops|BUG:|Unable to handle|watchdog.*bite|wdt' | tail -n 15)
if [ -n "$bad" ]; then
    say "  dmesg 异常行:"
    say "$bad" | sed 's/^/    /'
    if printf '%s' "$bad" | grep -q -i -E 'panic|oops|BUG:|Unable to handle'; then
        vfail STABILITY "dmesg 含 panic/oops/BUG"
    else
        vexp STABILITY "仅 wdt 相关行（对照历史 900e 研究）"
    fi
else
    vpass STABILITY "dmesg 无 panic/oops/BUG"
fi

# ---------------------------------------------------------------- 汇总
hdr SUMMARY "汇总"
say "  PASS=$PASS_N FAIL=$FAIL_N EXPECTED=$EXP_N"
say "  判定口径: FAIL=需修复; EXPECTED=预期内失败(固件/模块未就位等), 部署后重验"
say "r11s_onboard_check done."
exit 0
