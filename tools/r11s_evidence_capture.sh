#!/usr/bin/env bash
# ============================================================================
# r11s_evidence_capture.sh — fastboot boot 尝试后的设备侧只读取证脚本（草稿）
#
# 项目: Oppo R11s (Qualcomm SDM660 / arm64) 主线 bring-up
# 目录: /home/<user>/claude/r11/tools/
#
# 【用途】在用户【手动】执行 `fastboot boot <img>`（非破坏性 RAM boot）之后，
#   尽快用 adb 对设备做【只读】取证：
#     1. getprop（完整 dump + 关键属性）
#     2. dmesg（若 shell 权限允许；否则明确记录被拒）
#     3. /proc/device-tree 结构性 sanity（model / compatible / soc 下 USB 节点）
#     4. USB gadget 状态（UDC / DWC3 / configfs / pstore）
#   所有产物写入 out/test_evidence_<ts>/，并对每个文件计算 sha256 生成
#   SHA256SUMS 校验清单（与本项目 hash-first 约定一致）。
#
# 【安全边界，见 CLAUDE.md】
#   - 本脚本对设备仅执行【只读】命令（getprop / dmesg / ls / cat 等），
#     绝不写分区、不创建/绑定 gadget、不重启、不刷写、不进入 recovery。
#   - 本脚本【不】执行 fastboot boot；boot 动作由用户在取得当次确认后
#     手动执行，本脚本只负责 boot 尝试之后的事后取证。
#   - 若设备不在可用的 adb 状态（仍处于 fastboot、回落到官方 boot 但 adb
#     未授权、9008/EDL、或 RAM boot 用户态未起 adbd 等），脚本写入
#     NOT_IN_ADB 说明并仅记录 fastboot 侧只读上下文，不伪造设备证据。
#   - 9008 (EDL) 仅作原厂恢复路径；本脚本不涉及也不允许 EDL 刷写。
#
# 用法:
#   ./r11s_evidence_capture.sh                          # 默认取证
#   ./r11s_evidence_capture.sh "boot 尝试 1: img A"     # 附标签（建议含镜像名/时间）
#   ./r11s_evidence_capture.sh "label" "备注文字"       # 追加备注到 README
#   EVIDENCE_OUT=/path ./r11s_evidence_capture.sh ...   # 覆盖输出根目录
#
# 本脚本为草稿: 默认只取证，不执行任何设备写入；请先 review 后再使用。
# ============================================================================
set -u   # 未定义变量即报错（不使用 -e，让各步骤独立报告结果）

# ---------------------------------------------------------------------------
# 0. 配置
# ---------------------------------------------------------------------------
# 证据输出根目录（默认项目 out/）
OUT_ROOT="${EVIDENCE_OUT:-/home/<user>/claude/r11/out}"
TS="$(date +%Y%m%d_%H%M%S)"
EVID_DIR="${OUT_ROOT}/test_evidence_${TS}"

# 可选标签（如 boot 镜像名 / 尝试序号），记入 README
LABEL="${1:-未提供标签}"

# 可选备注（追加到 README）
NOTE="${2:-}"

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
info() { printf '[INFO]  %s\n' "$*"; }
note() { printf '[NOTE]  %s\n' "$*"; }
warn() { printf '[WARN]  %s\n' "$*" >&2; }

# 主机侧只读命令: 输出+退出码记录到 $EVID_DIR/$name
host_cmd() {
    local name="$1"; shift
    {
        printf '### [cmd] %s\n' "$*"
        "$@" 2>&1
        printf '### [rc] %s\n' "$?"
    } > "$EVID_DIR/$name" 2>&1
}

# 设备侧只读命令（经 adb shell，只读）: 输出+退出码记录到 $EVID_DIR/$name
# 用法: dev_sh <文件名> <远程 shell 片段...> （adb 会把各参数拼成一个远程命令）
dev_sh() {
    local name="$1"; shift
    {
        printf '### [cmd] adb shell %s\n' "$*"
        adb shell "$@" 2>&1
        printf '### [rc] %s\n' "$?"
    } > "$EVID_DIR/$name" 2>&1
}

# ---------------------------------------------------------------------------
# 步骤 (0): 打印说明 + 创建证据目录
# ---------------------------------------------------------------------------
cat <<'HEADER'
===========================================================================
 R11s — fastboot boot 尝试后的设备侧只读取证（草稿）
===========================================================================
 设备      : Oppo R11s (Qualcomm SDM660 / arm64)
 性质      : 仅对设备执行只读命令（getprop / dmesg / /proc/device-tree /
            USB gadget 状态）；不写分区、不改 gadget、不重启、不刷写
 输出      : out/test_evidence_<ts>/, 含 SHA256SUMS 校验清单
 前置      : boot 尝试已由用户在当次确认后手动执行；本脚本只负责取证
 边界      : 设备不在 adb 时只写 NOT_IN_ADB 说明，不伪造证据
===========================================================================
HEADER

mkdir -p "$EVID_DIR" || { warn "无法创建 $EVID_DIR"; exit 1; }

# README: 记录时间、host、标签与安全声明
{
    echo "R11s 设备侧只读取证 (post-fastboot-boot evidence capture)"
    echo "UTC 时间 : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "主机     : $(uname -srm)"
    echo "主机用户 : ${USER:-$(id -un)}"
    echo "标签     : $LABEL"
    echo "设备     : Oppo R11s (Qualcomm SDM660 / arm64)"
    echo "性质     : 本目录全部为设备【只读】取证产物；每个文件由 SHA256SUMS 校验"
    echo "说明     : 本脚本未执行 fastboot boot；请将实际 boot 命令与回显留档在 recon/"
    [ -n "$NOTE" ] && echo "备注     : $NOTE"
} > "$EVID_DIR/README.txt"

# ---------------------------------------------------------------------------
# 步骤 (1): 设备可达性判定（仅只读查询）
# ---------------------------------------------------------------------------
info "步骤(1): 判定设备状态 (adb devices -l + fastboot devices)"

host_cmd "01_adb_devices.txt" adb devices -l
host_cmd "02_fastboot_devices.txt" fastboot devices

# 解析 adb devices -l 输出，找可用的 device 状态
ADB_OUT="$(adb devices -l 2>&1)"
printf '%s\n' "$ADB_OUT" > "$EVID_DIR/01_adb_devices.txt"

ADB_SERIAL=""; ADB_STATE=""; ADB_READY=0
while read -r serial state rest; do
    case "$serial" in
        ""|"List"|"of"|"*") continue ;;
        *)
            if [ "$state" = "device" ]; then
                ADB_SERIAL="$serial"; ADB_STATE="$state"; ADB_READY=1; break
            fi
            if [ -z "$ADB_SERIAL" ]; then
                ADB_SERIAL="$serial"; ADB_STATE="${state:-unknown}"
            fi
            ;;
    esac
done <<EOF
$ADB_OUT
EOF

{
    echo "ADB_SERIAL=<SERIAL>"
    echo "ADB_STATE=${ADB_STATE:-NONE}"
    echo "ADB_READY=$ADB_READY"
    if ! command -v adb >/dev/null 2>&1; then
        echo "注意: 主机未检测到 adb 命令。"
    elif [ -z "$ADB_SERIAL" ]; then
        echo "判定: 设备不在 adb（未检测到任何 adb 设备）。"
    elif [ "$ADB_READY" -eq 0 ]; then
        echo "判定: adb 设备存在但状态=$ADB_STATE（unauthorized/offline 等），无法执行 shell 取证。"
    else
        echo "判定: adb 设备可用，开始设备侧只读取证。"
    fi
} > "$EVID_DIR/00_detection.txt"

# ---------------------------------------------------------------------------
# 步骤 (2): 设备侧只读取证（getprop / dmesg / /proc/device-tree / USB gadget）
# ---------------------------------------------------------------------------
if [ "$ADB_READY" -eq 1 ]; then
    info "步骤(2): 设备侧只读取证 (adb serial=<SERIAL>"

    # ---- 2.1 getprop -----------------------------------------------------
    dev_sh "10_getprop_full.txt" getprop
    dev_sh "11_getprop_key.txt" 'getprop | grep -E "^(ro\.boot\.|ro\.product\.|ro\.build\.|ro\.hardware|ro\.platform|ro\.board\.|ro\.soc|ro\.vendor\.|ro\.kernel|ro\.bootmode|ro\.secure|ro\.debuggable|sys\.oem|ro\.serialno|ro\.crypto)"'

    # ---- 2.2 内核/系统上下文 ---------------------------------------------
    dev_sh "20_uname.txt" uname -a
    dev_sh "21_kernel_version.txt" cat /proc/version
    dev_sh "22_cmdline.txt" cat /proc/cmdline
    dev_sh "23_uptime.txt" cat /proc/uptime

    # ---- 2.3 dmesg（若 shell 权限允许；否则记录被拒） ----------------------
    dev_sh "30_dmesg.txt" dmesg
    dev_sh "31_dmesg_tail.txt" 'dmesg 2>/dev/null | tail -n 300'

    # ---- 2.4 /proc/device-tree 结构性 sanity ------------------------------
    dev_sh "40_devicetree_top.txt" 'ls -la /proc/device-tree/'
    dev_sh "41_devicetree_model.txt" 'cat /proc/device-tree/model'
    dev_sh "42_devicetree_compatible.txt" 'cat /proc/device-tree/compatible'
    dev_sh "43_devicetree_soc_usb_nodes.txt" 'ls -la /proc/device-tree/soc/ | grep -iE "ssusb|dwc|qusb|usb|phy|gadget|a800000"'
    dev_sh "44_devicetree_usb_node_detail.txt" 'for n in /proc/device-tree/soc/*; do b=$(basename "$n"); case "$b" in *ssusb*|*dwc*|*qusb*|*usb*|*a800000*) echo "--- $n ---"; ls -la "$n" 2>&1;; esac; done'
    dev_sh "45_sys_firmware_devicetree.txt" 'ls -la /sys/firmware/devicetree 2>&1; echo "---"; readlink -f /proc/device-tree 2>&1'

    # ---- 2.5 USB gadget 状态（UDC / DWC3 / configfs） ---------------------
    dev_sh "50_udc_list.txt" 'ls -la /sys/class/udc/'
    dev_sh "51_udc_state.txt" 'for d in /sys/class/udc/*; do echo "=== $d ==="; for f in state current_speed maximum_speed function vendor product idVendor idProduct uevent; do printf "%s=" "$f"; cat "$d/$f" 2>&1; done; done'
    dev_sh "52_usb_gadget_configfs.txt" 'ls -la /sys/kernel/config/usb_gadget/ 2>&1'
    dev_sh "53_usb_gadget_udc_bind.txt" 'cat /sys/kernel/config/usb_gadget/*/UDC 2>&1'
    dev_sh "54_usb_gadget_tree.txt" 'find /sys/kernel/config/usb_gadget -maxdepth 3 2>/dev/null | head -n 200'
    dev_sh "55_dwc3_platform_drivers.txt" 'ls /sys/bus/platform/drivers/ 2>&1 | grep -iE "dwc3|msm|usb|phy|ci_hdrc"'
    dev_sh "56_dmesg_usb_filter.txt" 'dmesg 2>/dev/null | grep -iE "dwc3|usb_gadget|gadget|configfs|udc|a800000" | tail -n 300'

    # ---- 2.6 pstore / ramoops（早期崩溃证据，与 USB 互补） ----------------
    dev_sh "60_pstore.txt" 'ls -la /sys/fs/pstore 2>&1'
    dev_sh "61_ramoops_console.txt" 'for f in /sys/fs/pstore/console-ramoops*; do [ -e "$f" ] || continue; echo "--- $f ---"; cat "$f" 2>&1 | tail -n 300; done'
    dev_sh "62_ramoops_dmesg.txt" 'for f in /sys/fs/pstore/dmesg-ramoops*; do [ -e "$f" ] || continue; echo "--- $f ---"; head -c 4096 "$f" 2>&1; echo; done'

    # ---- 2.7 挂载/分区/bootmode 上下文 ------------------------------------
    dev_sh "70_mounts.txt" cat /proc/mounts
    dev_sh "71_partitions.txt" cat /proc/partitions
    dev_sh "72_bootmode.txt" 'getprop ro.bootmode; getprop ro.boot.mode; getprop ro.boot.verifiedbootstate; getprop ro.boot.slot_suffix; getprop ro.boot.bootdevice; getprop ro.boot.boot_devices'

else
    # ---------------------------------------------------------------------
    # 步骤 (3): 设备不在可用 adb 状态 —— 写入说明 + fastboot 只读上下文
    # ---------------------------------------------------------------------
    info "步骤(3): 设备不在可用 adb 状态，写入 NOT_IN_ADB 说明"

    {
        echo "设备不在可用的 adb 状态，未执行设备侧取证。"
        echo "时间   : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "标签   : $LABEL"
        echo ""
        echo "可能原因:"
        echo "  1) RAM boot 失败并回落到 fastboot/bootloader —— 用 fastboot 侧取证；"
        echo "  2) 回落到官方 Android 但 adb 未启用/未授权 —— 需在设备上允许 USB 调试；"
        echo "  3) RAM boot 用户态已起但未运行 adbd，或 USB 枚举未就绪；"
        echo "  4) 设备进入 9008/EDL —— 仅作原厂恢复路径，见 CLAUDE.md；"
        echo "  5) USB 线/口问题，或 adb server 未启动 (adb start-server)。"
        echo ""
        echo "已记录: adb devices、fastboot devices，以及（若在 fastboot 时）"
        echo "        只读 fastboot getvar all 上下文。"
    } > "$EVID_DIR/NOT_IN_ADB.txt"

    # 若设备确在 fastboot，追加只读 getvar 上下文（非写操作，不改变设备）
    if command -v fastboot >/dev/null 2>&1 \
       && grep -qE '[[:space:]]fastboot' "$EVID_DIR/02_fastboot_devices.txt" 2>/dev/null; then
        note "检测到 fastboot 设备，追加只读 getvar 上下文。"
        host_cmd "03_fastboot_getvar_all.txt" fastboot getvar all
    fi
fi

# ---------------------------------------------------------------------------
# 步骤 (4): 快速判定摘要（派生，仅供人工复核，不新增设备交互）
#           放在哈希之前生成，使摘要一并纳入 SHA256SUMS 校验清单
# ---------------------------------------------------------------------------
info "步骤(4): 生成快速判定摘要"

{
    echo "==== 快速判定摘要（派生；原始证据以各文件为准）===="
    echo "-- 内核版本 (/proc/version 首行) --"
    head -1 "$EVID_DIR/21_kernel_version.txt" 2>/dev/null || echo "(无 /proc/version 证据)"
    echo "-- device-tree model --"
    cat "$EVID_DIR/41_devicetree_model.txt" 2>/dev/null | head -5 || echo "(无)"
    echo "-- device-tree compatible --"
    cat "$EVID_DIR/42_devicetree_compatible.txt" 2>/dev/null | head -5 || echo "(无)"
    echo "-- UDC 列表 --"
    cat "$EVID_DIR/50_udc_list.txt" 2>/dev/null || echo "(无)"
    echo "-- UDC 状态(前 20 行) --"
    grep -E '^(===|---|state=|current_speed=)' "$EVID_DIR/51_udc_state.txt" 2>/dev/null | head -20 || echo "(无)"
    echo "-- dmesg 权限 --"
    if grep -qiE 'permission denied|operation not permitted|not permitted' "$EVID_DIR/30_dmesg.txt" 2>/dev/null; then
        echo "dmesg 被拒（内核权限限制），见 30_dmesg.txt"
    elif [ -s "$EVID_DIR/30_dmesg.txt" ]; then
        echo "dmesg 可用，行数: $(wc -l < "$EVID_DIR/30_dmesg.txt")"
    else
        echo "dmesg 输出为空（可能被拒或无日志）"
    fi
    echo "-- pstore --"
    if grep -qE 'console-ramoops|dmesg-ramoops' "$EVID_DIR/60_pstore.txt" 2>/dev/null; then
        echo "存在 ramoops 记录，见 61_/62_ 文件"
    else
        echo "未见 ramoops 记录（60_pstore.txt）"
    fi
} > "$EVID_DIR/99_summary.txt"

# ---------------------------------------------------------------------------
# 步骤 (5): 计算 sha256 校验清单
# ---------------------------------------------------------------------------
info "步骤(5): 计算 sha256 校验清单"

(
    cd "$EVID_DIR" || exit 1
    # 对目录下除 SHA256SUMS 自身以外的所有文件计算 sha256（相对路径）
    find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 \
        | sort -z | xargs -0 sha256sum
) > "$EVID_DIR/SHA256SUMS" 2>&1

if [ -s "$EVID_DIR/SHA256SUMS" ]; then
    info "验证校验清单:"
    ( cd "$EVID_DIR" && sha256sum -c SHA256SUMS ) > "$EVID_DIR/SHA256SUMS.verified" 2>&1
    if grep -q 'FAILED\|失败' "$EVID_DIR/SHA256SUMS.verified" 2>/dev/null; then
        warn "校验清单存在 FAILED 项，请人工复核。"
    else
        note "全部校验通过（OK）。"
    fi
else
    warn "SHA256SUMS 为空（证据目录中无文件），无法校验。"
fi

# ---------------------------------------------------------------------------
# 收尾
# ---------------------------------------------------------------------------
info "取证完成。"
note "证据目录: $EVID_DIR"
note "校验清单: $EVID_DIR/SHA256SUMS（见 SHA256SUMS.verified 复核结果）"
note "快速摘要: $EVID_DIR/99_summary.txt"
if [ "$ADB_READY" -eq 1 ]; then
    note "设备侧只读取证已写入; 请把结论留档到 recon/。"
else
    warn "设备不在可用 adb 状态；详见 $EVID_DIR/NOT_IN_ADB.txt。"
    note "未伪造任何设备证据；若需重新取证，先确认 adb 可用后重跑本脚本。"
fi
