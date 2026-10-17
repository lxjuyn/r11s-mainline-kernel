#!/usr/bin/env bash
# ============================================================================
# fastboot_boot_prep_draft.sh — 只读准备性质的 fastboot RAM boot 测试脚本（草稿）
#
# 项目: Oppo R11s (Qualcomm SDM660 / arm64) 主线 bring-up
# 目录: /home/<user>/claude/r11/tools/
#
# 【性质】本脚本是"准备性质草稿"：
#   - 默认模式只做【本地/只读】动作：记录设备状态、校验 boot.img 路径与
#     sha256、打印将要执行的命令、打印失败后的检查项。
#   - 绝不自动向设备执行任何写入/刷写/启动操作。
#   - fastboot boot 是【非破坏性 RAM boot】：仅把镜像载入内存临时启动，
#     不写任何分区；断电或重启即回到设备原有 boot（可回滚）。
#
# 【硬安全边界，见 CLAUDE.md】
#   - 当前阶段为资料取证与方案审阅；尚未建立 R11s 可测试镜像。
#   - 未取得完整且 hash 校验的原厂回滚材料前，禁止解锁、刷写、写分区、
#     生成或测试可刷镜像 —— 因此本脚本默认只打印，不执行 fastboot boot。
#   - 9008 (EDL) 仅作原厂恢复路径，本脚本完全不涉及。
#   - 任何会改变设备状态的动作，必须【需用户当次确认】后才能进行。
#
# 用法:
#   ./fastboot_boot_prep_draft.sh                              # 只读准备 + 打印（默认, 推荐）
#   BOOT_IMG=/path/to/boot.img ./fastboot_boot_prep_draft.sh   # 指定镜像
#   EXPECTED_SHA256=<hash> ./fastboot_boot_prep_draft.sh       # 追加 sha256 交叉校验
#
# 警告: 本脚本默认模式绝不执行设备操作；fastboot boot 仅打印。
#       只有用户显式传入 --boot 且设备确在 fastboot 模式、镜像 hash 通过、
#       且用户在终端当次键入确认后，才会执行 RAM boot。
# ============================================================================
set -u   # 未定义变量即报错（不使用 -e，让各步骤独立报告结果）

# ---------------------------------------------------------------------------
# 0. 配置
# ---------------------------------------------------------------------------
# 将要使用的 boot.img 路径（默认留空，必须显式指定）。
# 注意: 当前阶段尚无经审阅的 R11s 可测试镜像；此路径仅作准备，脚本不会自动使用。
BOOT_IMG="${BOOT_IMG:-}"

# 期望的 boot.img sha256（可选，用于交叉校验；证据优先）
EXPECTED_SHA256="${EXPECTED_SHA256:-}"

# 只读日志输出（仅写入本地文件，不改设备）
OUT_DIR="${OUT_DIR:-/home/<user>/claude/r11/out}"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${OUT_DIR}/fastboot_prep_${TS}.log"

# RAM boot 执行开关: 仅当显式传入 --boot 时才可能进入（仍需交互确认）
DO_BOOT=0
if [ "${1:-}" = "--boot" ]; then
    DO_BOOT=1
fi

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
info() { printf '[INFO]  %s\n' "$*"; }
note() { printf '[NOTE]  %s\n' "$*"; }
warn() { printf '[WARN]  %s\n' "$*" >&2; }

# 同时输出到屏幕并记录到本地日志（log 文件在 out/，非设备文件）
log()  { printf '%s\n' "$*" | tee -a "$LOG_FILE"; }

# ---------------------------------------------------------------------------
# 步骤 (0): 打印安全边界与用法说明
# ---------------------------------------------------------------------------
cat <<'HEADER'
===========================================================================
 fastboot RAM boot — 只读准备性质测试脚本（草稿）
===========================================================================
 设备      : Oppo R11s (Qualcomm SDM660 / arm64)
 操作      : 非破坏性 RAM boot（fastboot boot）
 影响      : 仅把内核/DTB/initramfs 载入内存临时启动，不写任何分区；
             重启后回到设备原有 boot，可回滚
 默认模式  : 只读查询 + 打印，不对设备执行任何操作
 安全要求  : 任何设备操作均【需用户当次确认】
===========================================================================
HEADER

# ---------------------------------------------------------------------------
# 步骤 (1/4): 记录设备状态（adb devices + fastboot devices，均为只读查询）
# ---------------------------------------------------------------------------
info "步骤(1/4): 记录设备状态 (adb devices + fastboot devices)"

log "--- adb devices ---"
ADB_OUT="$(adb devices 2>&1)"
log "$ADB_OUT"

log ""
log "--- fastboot devices ---"
FASTBOOT_OUT="$(fastboot devices 2>&1)"
log "$FASTBOOT_OUT"

# 判定设备是否已在 fastboot 模式（只读判定，不改设备）
FASTBOOT_SEEN=0
if printf '%s\n' "$FASTBOOT_OUT" | grep -v '^$' | grep -qv 'no permissions\|not found\|command not found'; then
    FASTBOOT_SEEN=1
fi
if [ "$FASTBOOT_SEEN" -eq 1 ]; then
    note "检测到 fastboot 设备（见上）。"
else
    note "未检测到 fastboot 设备；如需 RAM boot，先进入 fastboot（通常: 关机后 音量- + 电源）。"
fi

# ---------------------------------------------------------------------------
# 步骤 (2/4): 打印将要使用的 boot.img 路径与 sha256
# ---------------------------------------------------------------------------
info "步骤(2/4): 打印将要使用的 boot.img 路径与 sha256"

if [ -z "$BOOT_IMG" ]; then
    warn "BOOT_IMG 未指定。请在运行前设置: BOOT_IMG=/path/to/boot.img"
    note "脚本仅做打印准备；未指定镜像时不会进入 boot 分支。"
else
    note "boot.img 路径: $BOOT_IMG"
    if [ -f "$BOOT_IMG" ]; then
        ACTUAL_SHA256="$(sha256sum "$BOOT_IMG" | awk '{print $1}')"
        log "sha256: $ACTUAL_SHA256"
        note "文件大小(字节): $(stat -c%s "$BOOT_IMG")"
        if [ -n "$EXPECTED_SHA256" ]; then
            if [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ]; then
                note "sha256 与期望值一致。"
            else
                warn "sha256 与期望值不一致（期望 $EXPECTED_SHA256），拒绝后续 boot。"
            fi
        else
            note "未提供 EXPECTED_SHA256，仅记录实际值；建议比对原厂 hash。"
        fi
    else
        warn "文件不存在: $BOOT_IMG"
    fi
fi

# ---------------------------------------------------------------------------
# 步骤 (3/4): 打印命令 `fastboot boot <img>` 及其说明
#             （若设备已在 fastboot）
# ---------------------------------------------------------------------------
info "步骤(3/4): 打印命令 fastboot boot <img> 及其说明"

note "命令:"
printf '    fastboot boot %s\n' "$BOOT_IMG"
note ""
note "说明:"
note "  * 非破坏性 RAM boot: 仅把镜像载入内存临时启动，不写 boot/recovery 等分区；"
note "    重启或断电即回到设备原有 boot，可完全回滚。"
note "  * 前提: 设备已在 fastboot 模式（见步骤1输出），且 bootloader 已解锁并支持 fastboot boot。"
note "  * 当前项目阶段（取证/审阅）尚未授权测试任何可刷镜像，默认只打印本命令。"

# 执行 RAM boot 的完整安全门禁（默认不触发）:
#   --boot 显式传入 + 设备在 fastboot + 镜像存在 + hash 校验通过 + 用户当次确认
if [ "$DO_BOOT" -eq 1 ] && [ "$FASTBOOT_SEEN" -eq 1 ] \
   && [ -n "$BOOT_IMG" ] && [ -f "$BOOT_IMG" ]; then

    # hash 交叉校验（若提供期望值）
    if [ -n "$EXPECTED_SHA256" ] && [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
        warn "sha256 校验未通过，拒绝执行 RAM boot。"
    else
        warn "即将执行非破坏性 RAM boot；【需用户当次确认】。"
        read -r -p "请输入 yes 以当次确认执行（其它输入则跳过）: " CONFIRM
        if [ "$CONFIRM" = "yes" ]; then
            note "执行: fastboot boot $BOOT_IMG"
            fastboot boot "$BOOT_IMG"
        else
            note "用户未当次确认，跳过执行（RAM boot 未发生，设备未改变）。"
        fi
    fi
else
    note "本脚本默认不执行 fastboot boot。"
    note "请复制上面命令，由用户取得当次确认后手动执行。"
fi

# ---------------------------------------------------------------------------
# 步骤 (4/4): 打印失败后的检查项
# ---------------------------------------------------------------------------
info "步骤(4/4): 打印失败后的检查项"

cat <<'FAILCHECK'

----- A. dmesg 不可用时的替代证据路径 -----
  注意: R11s 主调试走 USB gadget (DWC3)，但它在 DWC3 probe 前无法覆盖早期
        崩溃；因此早期失败必须依赖下列 bootloader/板级可见证据。
  1. pstore/ramoops:
     * 若内核开启了 PSTORE_CONSOLE / PSTORE_RAM，重启后查看:
         ls /sys/fs/pstore/                 # console-ramoops*, dmesg-ramoops*
     * RAM boot 崩溃后正常重启回官方 boot 时，官方 boot 一般不会保留你的
       ramoops 内容 —— 需要先在内核配置里确保 ramoops reserved-memory 已取证
       并预留（见 recon/ 中的 reserved-memory 取证记录）。
  2. framebuffer / 早期控制台:
     * 配置 fbcon / 简单 framebuffer，把早期日志打到屏幕，属 bootloader 可见证据。
  3. logcat / adb（仅当 RAM boot 进入了用户态且 USB 网络已起来）:
     * adb devices 后: adb shell dmesg; adb shell logcat -d
  4. fastboot 侧只读信息:
     * fastboot getvar all            # 只读，不改变设备
  5. 序列口 (UART/TTL): R11s 难以引出，不作为主调试路线（见 CLAUDE.md）。

----- B. 重试步骤 -----
  1. 再次确认设备确在 fastboot: fastboot devices
  2. 更换 USB 线 / 直连主板口（避免 hub），确认驱动与线缆稳定。
  3. 复位后重进 fastboot:
     * 若 RAM boot 卡死: 长按电源 ~10s 强制断电，再进入 fastboot。
     * fastboot reboot bootloader      # 设备仍在 fastboot 时回到 bootloader
     * 然后重跑: fastboot boot <img>
  4. 再次核对镜像: sha256sum <img>（RAM boot 失败不代表镜像 hash 变化，但仍需复核）。

----- C. 回滚到官方 boot（RAM boot 的天然回滚路径）-----
  1. RAM boot 不写任何分区，因此回滚就是"不再 RAM boot":
       fastboot reboot                # 正常重启 → 设备回到 boot 分区的官方 boot
  2. 可选只读确认槽位（A/B 设备才需要）:
       fastboot getvar current-slot
  3. 若发生意外写入（不应发生），需用原厂 boot.img 恢复:
       fastboot flash boot <官方 boot.img>
     —— 该操作会写分区，必须【需用户当次确认】并提供原厂镜像与 hash。

----- D. 结论记录 -----
  请把上述证据、命令回显、hash 与结论写入 recon/，切勿把搜索猜测升级为设备事实。
FAILCHECK

# ---------------------------------------------------------------------------
# 收尾: 日志位置与提示
# ---------------------------------------------------------------------------
info "只读准备脚本完成（本脚本未自动执行任何设备操作）。"
note "日志: $LOG_FILE"
