#!/usr/bin/env bash
set -u
DEV=/dev/ttyACM0
LOG="${1:?usage}"
stty -F "$DEV" 115200 raw -echo 2>/dev/null || true
: > "$LOG"
cat "$DEV" >> "$LOG" 2>/dev/null &
RXPID=$!
run() { printf '%s\n' "$1" > "$DEV"; sleep "${2:-2}"; }
printf '\n' > "$DEV"; sleep 1
run 'echo R0; grep -E "rmi4|0020" /proc/interrupts; echo R1' 2
run '(timeout 12 cat /dev/input/event0 | od -A d -t x1 | head -40; echo EVENT_DONE) > /dev/console &' 1
echo "[host] event0 抓取已在设备端后台启动 12s，请立即在屏幕上划动"
sleep 14
run 'echo R2; grep -E "rmi4|0020" /proc/interrupts; echo R3' 2
sleep 1
kill $RXPID 2>/dev/null
echo "[done] $(date +%T) -> $LOG"
