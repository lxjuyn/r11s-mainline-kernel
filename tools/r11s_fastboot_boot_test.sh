#!/usr/bin/env bash
# ============================================================================
# r11s_fastboot_boot_test.sh — Oppo R11s fastboot RAM-boot 测试脚本（主机侧）
#
# 项目: Oppo R11s (Qualcomm SDM660 / arm64) 主线 bring-up
# 目录: /home/<user>/claude/r11/tools/
#
# 【性质】主机侧编排脚本，负责按序完成一次 `fastboot boot` 非破坏性 RAM boot 测试：
#   (1) 捕获前状态   —— adb devices / fastboot devices / fastboot getvar all（只读基线）
#   (2) 校验 boot.img —— 存在性 / 大小 / SHA-256（与期望值交叉比对）
#   (3) 启动决策     —— 默认只【提示用户】手动执行；或用户显式传 --execute
#                       且满足全部门禁后执行 `fastboot boot <img>`
#   (4) 捕获后状态   —— post fastboot/adb 状态与 dmesg 等价证据（adb shell dmesg/logcat）
#   (5) 清理/回滚    —— 输出回滚与清理说明，写证据目录与 summary
#
# 【硬安全边界，见 CLAUDE.md / recon/P0_B_FASTBOOT_EVIDENCE_REPORT.md】
#   - 默认 dry-run：只做只读采集 + 打印，绝不执行 fastboot boot。
#   - 设备操作必须【显式传 --execute】才可能执行；且按项目规则仍须用户
#     当次交互确认（除非同时显式传 --yes —— 自动化慎用，属规则内的显式覆盖）。
#   - `fastboot boot` 是非破坏性 RAM boot：仅把镜像载入内存临时启动，不写任何分区，
#     重启/断电即回滚到设备 boot 分区原有 boot。但【本设备 fastboot boot 是否被
#     bootloader 支持尚未实测】—— 本测试正是为了确认该能力，属于改变设备运行状态
#     的操作，必须当次批准。
#   - 提供了 --sha256 且与实测不一致时，脚本【硬拒绝】执行。
#   - 本脚本绝不 flash 分区、绝不写 boot/recovery/vbmeta、绝不进入或绕过 9008 (EDL)。
#   - 证据仅落盘到本机 out/ 目录，不改设备上的任何文件。
#
# 用法:
#   ./r11s_fastboot_boot_test.sh --boot-image <path>                         # dry-run（默认）
#   ./r11s_fastboot_boot_test.sh --boot-image <path> --sha256 <hash>         # 追加交叉校验
#   ./r11s_fastboot_boot_test.sh --boot-image <path> --execute               # 显式执行 RAM boot
#   ./r11s_fastboot_boot_test.sh --boot-image <path> --execute --yes         # 自动化（跳过当次确认）
#   ./r11s_fastboot_boot_test.sh --dry-run --boot-image <path>               # 等价于默认
#
# 选项:
#   --boot-image <path>   要 RAM boot 的 boot 镜像（必需）
#   --sha256 <hash>       期望 SHA-256（可选；提供后不匹配即拒绝执行）
#   --out-dir <path>      证据输出根目录（默认 $OUT_DIR）
#   --wait-seconds <N>    boot 后轮询 adb 上线的秒数，0=不轮询（默认 30）
#   --execute             执行 fastboot boot（默认只提示，不执行）
#   --yes                 跳过当次交互确认（仅配合 --execute；自动化慎用）
#   --dry-run             强制 dry-run（默认即此模式）
#   -h|--help             打印本说明
#
# 退出码: 0=正常完成；1=参数/校验失败；2=执行被拒绝；3=boot 命令本身返回非零
# ============================================================================
set -u   # 未定义变量即报错（不使用 -e，让各步骤独立报告结果）

# ---------------------------------------------------------------------------
# 0. 默认配置
# ---------------------------------------------------------------------------
BOOT_IMG=""
EXPECTED_SHA256=""
OUT_DIR="${OUT_DIR:-/home/<user>/claude/r11/out}"
WAIT_SECONDS=30
MODE="dryrun"          # dryrun（默认）| execute
SKIP_CONFIRM=0
TS="$(date +%Y%m%d_%H%M%S)"
EVIDENCE_DIR="${OUT_DIR}/r11s_fastboot_boot_${TS}"
LOG_FILE="${EVIDENCE_DIR}/script.log"

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
info() { printf '[INFO]  %s\n' "$*"; }
note() { printf '[NOTE]  %s\n' "$*"; }
warn() { printf '[WARN]  %s\n' "$*" >&2; }
fail() { printf '[FAIL]  %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'USAGE'
用法:
  ./r11s_fastboot_boot_test.sh --boot-image <path>                         # dry-run（默认）
  ./r11s_fastboot_boot_test.sh --boot-image <path> --sha256 <hash>         # 追加交叉校验
  ./r11s_fastboot_boot_test.sh --boot-image <path> --execute               # 显式执行 RAM boot
  ./r11s_fastboot_boot_test.sh --boot-image <path> --execute --yes         # 自动化（跳过当次确认）

选项:
  --boot-image <path>   要 RAM boot 的 boot 镜像（必需）
  --sha256 <hash>       期望 SHA-256（可选；提供后不匹配即拒绝执行）
  --out-dir <path>      证据输出根目录（默认 /home/<user>/claude/r11/out）
  --wait-seconds <N>    boot 后轮询 adb 上线的秒数，0=不轮询（默认 30）
  --execute             执行 fastboot boot（默认只提示，不执行）
  --yes                 跳过当次交互确认（仅配合 --execute；自动化慎用）
  --dry-run             强制 dry-run（默认即此模式）
  -h|--help             打印本说明
USAGE
    exit "${1:-0}"
}

# 证据采集：把命令输出同时打印并写入 EVIDENCE_DIR/<文件名>
capture_cmd() {
    local desc="$1" fname="$2"; shift 2
    info "$desc"
    {
        echo "### $desc  ($(date '+%Y-%m-%d %H:%M:%S'))"
        echo "### cmd: $*"
        "$@" 2>&1
        echo "### exit=$?"
    } | tee "$EVIDENCE_DIR/$fname"
}

# ---------------------------------------------------------------------------
# 1. 解析参数
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --boot-image)   BOOT_IMG="${2:?--boot-image 需要路径}";            shift 2 ;;
        --sha256)       EXPECTED_SHA256="${2:?--sha256 需要 hash}";        shift 2 ;;
        --out-dir)      OUT_DIR="${2:?--out-dir 需要路径}";                shift 2 ;;
        --wait-seconds) WAIT_SECONDS="${2:?--wait-seconds 需要秒数}";      shift 2 ;;
        --execute)      MODE="execute";                                    shift ;;
        --yes)          SKIP_CONFIRM=1;                                    shift ;;
        --dry-run)      MODE="dryrun";                                     shift ;;
        -h|--help)      usage 0 ;;
        *)              warn "未知参数: $1"; usage 1 ;;
    esac
done

[ -n "$BOOT_IMG" ] || usage 1
[ "$WAIT_SECONDS" -ge 0 ] 2>/dev/null || { warn "WAIT_SECONDS 需为非负整数"; usage 1; }

mkdir -p "$EVIDENCE_DIR"
: > "$LOG_FILE"

# 屏幕+日志双写（日志在 EVIDENCE_DIR，本机文件）
log() { printf '%s\n' "$*" | tee -a "$LOG_FILE"; }

# ---------------------------------------------------------------------------
# 2. 安全边界与测试说明
# ---------------------------------------------------------------------------
cat <<HEADER | tee -a "$LOG_FILE"
===========================================================================
 r11s fastboot RAM-boot 测试（主机侧编排）
===========================================================================
 设备      : Oppo R11s (Qualcomm SDM660 / arm64)
 操作      : 非破坏性 RAM boot: fastboot boot <img>
 影响      : 仅把内核/DTB/initramfs 载入内存临时启动，不写任何分区；
             重启/断电后回到设备 boot 分区原有 boot，可回滚
 模式      : ${MODE}（dryrun=只读采集+提示；execute=满足门禁后执行）
 证据目录  : $EVIDENCE_DIR
 安全要求  : 不写分区；不碰 9008/EDL；设备操作须用户当次批准
 未证实项  : 本设备 fastboot boot 是否被 bootloader 支持尚未实测
             —— 本次测试正是对该能力的确认，需显式授权
===========================================================================
HEADER

# ---------------------------------------------------------------------------
# 3. 步骤 (1/5): 捕获前状态（全部只读）
# ---------------------------------------------------------------------------
info "步骤(1/5): 捕获前状态 (adb devices + fastboot devices + getvar all)"

capture_cmd "前状态 adb devices"  pre_adb_devices.txt  adb devices -l
capture_cmd "前状态 fastboot devices" pre_fastboot_devices.txt fastboot devices -l

FASTBOOT_OUT="$(fastboot devices -l 2>&1)"
FASTBOOT_SEEN=0
if printf '%s\n' "$FASTBOOT_OUT" | grep -q . \
   && ! printf '%s\n' "$FASTBOOT_OUT" | grep -qi 'no permissions\|not found\|command not found'; then
    FASTBOOT_SEEN=1
fi
[ "$FASTBOOT_SEEN" -eq 1 ] \
    && note "检测到 fastboot 设备（见 pre_fastboot_devices.txt）。" \
    || note "未检测到 fastboot 设备；执行模式将在此拒绝（先进入 fastboot）。"

# 只读基线：完整分区表与变量（设备须在 fastboot 才返回数据）
capture_cmd "前状态 fastboot getvar all（只读）" pre_getvar_all.txt fastboot getvar all

# ---------------------------------------------------------------------------
# 4. 步骤 (2/5): 校验 boot.img（存在性 / 大小 / SHA-256 / magic）
# ---------------------------------------------------------------------------
info "步骤(2/5): 校验 boot.img 与 SHA-256"

[ -f "$BOOT_IMG" ] || fail "boot.img 不存在: $BOOT_IMG"

SIZE="$(stat -c%s "$BOOT_IMG")"
ACTUAL_SHA256="$(sha256sum "$BOOT_IMG" | awk '{print $1}')"
{
    echo "boot.img      : $BOOT_IMG"
    echo "size (bytes)  : $SIZE"
    echo "sha256        : $ACTUAL_SHA256"
    [ -n "$EXPECTED_SHA256" ] && echo "expected sha256: $EXPECTED_SHA256"
    echo "expected match: $([ -n "$EXPECTED_SHA256" ] && [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] && echo YES || echo NO)"
    echo "magic         : $(head -c 8 "$BOOT_IMG" 2>/dev/null | tr -d '\000')"
} | tee "$EVIDENCE_DIR/boot_img_sha256.txt"

note "boot.img: $BOOT_IMG  (${SIZE} bytes)"
note "SHA-256: $ACTUAL_SHA256"
if [ -n "$EXPECTED_SHA256" ]; then
    if [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ]; then
        HASH_OK=1; note "SHA-256 与期望值一致。"
    else
        HASH_OK=0; warn "SHA-256 与期望值【不一致】！期望 $EXPECTED_SHA256"
        note "按项目规则硬拒绝执行（本次及后续 --execute 均不可用）。"
    fi
else
    HASH_OK=1
    note "未提供 --sha256，仅记录实际值；建议比对原厂 hash（见 recon/P0_C_* 审计）。"
fi

case "$(head -c 8 "$BOOT_IMG" 2>/dev/null | tr -d '\000')" in
    ANDROID!*) note "magic=ANDROID!（标准 Android boot header，v1/v2/v3 常见）。" ;;
    *)         note "magic 非标准 'ANDROID!'，仅作记录；打包工具/版本差异待核实。" ;;
esac

# ---------------------------------------------------------------------------
# 5. 步骤 (3/5): RAM boot 决策（dry-run 只提示；execute 过门禁后执行）
# ---------------------------------------------------------------------------
info "步骤(3/5): RAM boot 决策"

BOOT_CMD="fastboot boot $BOOT_IMG"

if [ "$MODE" = "dryrun" ]; then
    log ""
    log "===== dry-run 提示（本脚本未执行任何设备操作）====="
    log "待执行命令:"
    log "    $BOOT_CMD"
    log ""
    log "前置条件:"
    log "    1. 设备已进入 fastboot（见 pre_fastboot_devices.txt）。"
    log "    2. bootloader 已解锁（recon/P0_B 实测 unlocked=yes）。"
    log "    3. fastboot boot 支持尚未实测——需当次批准后才可发起。"
    log "回滚: RAM boot 不写分区，重启即回官方 boot；长按电源 ~10s 可强制断电。"
    log "请由用户在取得当次确认后手动执行上面的命令，或改传 --execute 由本脚本执行。"
    EXIT_CODE=0
else
    # 门禁 1: 镜像有效且 hash 通过
    [ "$HASH_OK" -eq 1 ] || { warn "hash 校验未通过，拒绝执行 RAM boot。"; EXIT_CODE=2; }
    # 门禁 2: 设备确在 fastboot
    [ "$FASTBOOT_SEEN" -eq 1 ] || { warn "未检测到 fastboot 设备，拒绝执行。"; EXIT_CODE=2; }

    if [ "${EXIT_CODE:-0}" -eq 0 ]; then
        # 展示命令/目标/回滚路径/风险，并取得当次确认（CLAUDE.md 硬规则）
        log ""
        log "===== 即将执行非破坏性 RAM boot ====="
        log "命令        : $BOOT_CMD"
        log "目标        : 内存（RAM）临时启动，不写 boot/recovery/vbmeta 等任何分区"
        log "回滚路径    : 重启/断电即回到设备 boot 分区原有 boot；卡死时长按电源 ~10s"
        log "风险        : 此操作改变设备运行状态（临时启动自编译内核）；"
        log "              设备随后可能停留在黑屏/卡死状态，需手动重启恢复"
        log "            : bootloader 可能拒绝非原厂镜像（unlocked=yes 但不保证接受）"
        if [ "$SKIP_CONFIRM" -eq 1 ]; then
            note "--yes 已传：跳过当次交互确认（自动化模式，使用者自担风险）。"
            CONFIRM="yes"
        else
            warn "按项目规则需要当次确认。"
            read -r -p "请输入 yes 当次确认执行（其它输入则取消）: " CONFIRM
        fi
        if [ "$CONFIRM" = "yes" ]; then
            info "执行: $BOOT_CMD"
            capture_cmd "执行 fastboot boot" boot_execution.txt fastboot boot "$BOOT_IMG"
            FASTBOOT_BOOT_EXIT=$?
            if [ "$FASTBOOT_BOOT_EXIT" -ne 0 ]; then
                note "fastboot boot 返回非零 ($FASTBOOT_BOOT_EXIT)。注意: RAM boot 常因设备断开连接"
                note "而报错，即使镜像已成功加载；请结合 boot_execution.txt 与后状态判断。"
                EXIT_CODE=3
            else
                EXIT_CODE=0
            fi
        else
            warn "未当次确认，取消执行（设备未改变）。"
            EXIT_CODE=2
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 6. 步骤 (4/5): 捕获后状态与 dmesg 等价证据
# ---------------------------------------------------------------------------
info "步骤(4/5): 捕获后状态与 dmesg 等价证据"

sleep 2
capture_cmd "后状态 fastboot devices" post_fastboot_devices.txt fastboot devices -l
capture_cmd "后状态 adb devices"      post_adb_devices.txt      adb devices -l

# 轮询 adb 上线（RAM boot 进入用户态后 adb 应出现）
ADB_SEEN=0
if [ "$WAIT_SECONDS" -gt 0 ]; then
    note "轮询 adb 上线（最多 ${WAIT_SECONDS}s，可 --wait-seconds 调整）..."
    for ((i = 0; i < WAIT_SECONDS; i += 2)); do
        if adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {found=1} END{exit !found}'; then
            ADB_SEEN=1
            note "adb 设备已上线（约第 ${i}s）。"
            break
        fi
        sleep 2
    done
    [ "$ADB_SEEN" -eq 1 ] || note "在 ${WAIT_SECONDS}s 内未观察到 adb 设备上线。"
fi

if [ "$ADB_SEEN" -eq 1 ]; then
    note "设备以 adb 模式在线，采集 dmesg 等价证据。"
    capture_cmd "adb get-state"      post_adb_getstate.txt adb get-state
    capture_cmd "adb shell dmesg"    post_dmesg.txt        adb shell dmesg
    capture_cmd "adb shell uptime"   post_uptime.txt       adb shell uptime
    capture_cmd "adb logcat -d"      post_logcat.txt       adb logcat -d
else
    note "adb 未上线；dmesg/logcat 证据不可得。早期崩溃证据需走 ramoops/pstore、"
    note "framebuffer 或 bootloader 可见路径（见 CLAUDE.md USB-first 说明）。"
fi

# ---------------------------------------------------------------------------
# 7. 步骤 (5/5): 清理与回滚说明 + 证据汇总
# ---------------------------------------------------------------------------
info "步骤(5/5): 清理与回滚说明"

log ""
log "===== 清理与回滚说明 ====="
log "  * RAM boot 不写任何分区，无需设备侧清理；证据均在主机侧目录:"
log "      $EVIDENCE_DIR"
log "  * 回滚（回到官方/原 boot）:"
log "      正常:  fastboot reboot        （RAM boot 结束后重启即回 boot 分区原镜像）"
log "      卡死:  长按电源 ~10s 强制断电，再按音量- + 电源进入 fastboot"
log "      fastboot 内重进:  fastboot reboot bootloader"
log "  * 若 RAM boot 被拒绝或设备黑屏，先复查:"
log "      fastboot devices          （确认仍在 fastboot）"
log "      sha256sum $BOOT_IMG  （复核镜像 hash 未变）"
log "      recon/P0_B_FASTBOOT_EVIDENCE_REPORT.md （fastboot 能力基线）"
log "  * 意外写入（本脚本不应发生）时的恢复路径:"
log "      需原厂 boot.img + 用户当次确认: fastboot flash boot <官方 boot.img>"
log "  * 结论与证据请写入 recon/；不要把搜索/推测升级为设备事实。"

# 汇总文件
cat > "$EVIDENCE_DIR/summary.txt" <<EOF
Test: r11s fastboot RAM boot
Date: $(date '+%Y-%m-%d %H:%M:%S')
Mode: $MODE
Boot image : $BOOT_IMG
Size       : ${SIZE:-n/a} bytes
SHA-256    : ${ACTUAL_SHA256:-n/a}
Expected   : ${EXPECTED_SHA256:-none}
Hash match : $([ -n "${HASH_OK:-}" ] && [ "$HASH_OK" -eq 1 ] && echo YES || echo NO)
Fastboot pre : ${FASTBOOT_SEEN:-0}
Fastboot boot exit : ${FASTBOOT_BOOT_EXIT:-not-run}
Adb post     : ${ADB_SEEN:-0}
Evidence dir : $EVIDENCE_DIR
EOF
log ""
note "脚本完成。模式=${MODE}，退出码=${EXIT_CODE:-0}。"
note "证据目录: $EVIDENCE_DIR"
exit "${EXIT_CODE:-0}"
