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
run 'echo S0; date; grep -E "rmi4|0020" /proc/interrupts; echo S1' 2
run '(date; timeout 20 cat /dev/input/event0 | od -A d -t x1 | head -40; date; echo EVENT_DONE2) > /dev/console' 24
run 'echo S2; date; grep -E "rmi4|0020" /proc/interrupts; echo S3' 2
sleep 1
kill $RXPID 2>/dev/null
echo "[done] $(date +%T) -> $LOG"
