#!/usr/bin/env bash
# 救援 shell 一次性命令收发器：后台抓输出，逐条发命令（带标记），输出重定向到日志。
set -u
DEV=/dev/ttyACM0
LOG="${1:?usage: rescue_send.sh <logfile>}"
stty -F "$DEV" 115200 raw -echo 2>/dev/null || true
: > "$LOG"
cat "$DEV" >> "$LOG" 2>/dev/null &
RXPID=$!
sleep 0.5
printf '\n' > "$DEV"; sleep 1
echo "" >> "$LOG"; echo "=== $(date +%T) ===" >> "$LOG"
run() {
  printf '%s\n' "$1" > "$DEV"
  sleep "${2:-2}"
}
run 'echo MARK_START; cat /proc/version; echo MARK_END' 2
run 'echo MARK_DMESG_START; dmesg | grep -iE "rmi4|f12" | tail -40; echo MARK_DMESG_END' 2
run 'echo MARK_F12_START; ls -l /sys/bus/rmi4/devices/ 2>&1; ls -l /sys/bus/rmi4/devices/rmi4-00.fn12/driver 2>&1; echo MARK_F12_END' 2
run 'echo MARK_INPUT_START; cat /proc/bus/input/devices; echo MARK_INPUT_END' 2
run 'echo MARK_IRQ_START; grep -E "rmi4|0020" /proc/interrupts; echo MARK_IRQ_END' 2
sleep 1
kill $RXPID 2>/dev/null
echo "[done] $(date +%T) -> $LOG"
