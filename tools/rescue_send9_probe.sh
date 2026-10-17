#!/usr/bin/env bash
# 任务 23 取证 1：救援环境探测（只读）
set -u
DEV=/dev/ttyACM0
LOG="${1:?usage: $0 <logfile>}"
stty -F "$DEV" 115200 raw -echo 2>/dev/null || true
: > "$LOG"
cat "$DEV" >> "$LOG" 2>/dev/null &
RXPID=$!
run() { printf '%s\n' "$1" > "$DEV"; sleep "${2:-2}"; }
printf '\n' > "$DEV"; sleep 1
run 'echo T0; uname -a; echo T1' 2
run 'echo T2; ls /tmp/rmi4dump_raw /tmp/rmi4read_raw /usr/bin/i2cget /sbin/i2cget 2>&1; ls /dev/i2c-* 2>&1; echo T3' 2
run 'echo T4; dmesg | grep -iE "unstable PDT|Duplicate PDT|Initializing F|rmi4" | head -30; echo T5' 3
run 'echo T6; ls /sys/bus/rmi4/devices/ 2>&1; cat /sys/class/input/event0/device/capabilities/ev /sys/class/input/event0/device/capabilities/abs 2>&1; echo T7' 2
run 'echo TEND' 2
sleep 1
kill $RXPID 2>/dev/null
echo "[done] -> $LOG"
