#!/usr/bin/env bash
# v8 轮取证：bind 复现 F12 probe 报错 + 重试路径鉴别 + PDT/query 现场
set -u
DEV=/dev/ttyACM0
LOG="${1:?usage}"
stty -F "$DEV" 115200 raw -echo 2>/dev/null || true
: > "$LOG"
cat "$DEV" >> "$LOG" 2>/dev/null &
RXPID=$!
run() { printf '%s\n' "$1" > "$DEV"; sleep "${2:-2}"; }
printf '\n' > "$DEV"; sleep 1
# 1) bind 复现（先解绑兜底，再绑定触发 probe）
run 'echo B0; ls -l /sys/bus/rmi4/devices/rmi4-00.fn12/driver 2>&1; echo B1' 2
run 'echo rmi4-00.fn12 > /sys/bus/rmi4/drivers/rmi4_f12/bind 2>&1; echo B2' 3
# 2) 新鲜报错全文（含重试日志）
run 'echo D0; dmesg | grep -iE "fn12|f12|retry|Query|Descriptor|0020" | tail -50; echo D1' 4
# 3) bind 后状态
run 'echo S0; ls -l /sys/bus/rmi4/devices/rmi4-00.fn12/ 2>&1; echo S1' 2
run 'echo S2; cat /sys/class/input/event0/device/capabilities/ev /sys/class/input/event0/device/capabilities/abs 2>&1; echo S3' 2
# 4) 再绑一次确认确定性（间隔 2s）
run 'sleep 2; echo rmi4-00.fn12 > /sys/bus/rmi4/drivers/rmi4_f12/bind 2>&1; echo B3' 4
run 'echo D2; dmesg | tail -25; echo D3' 3
sleep 1
kill $RXPID 2>/dev/null
echo "[done] $(date +%T) -> $LOG"
