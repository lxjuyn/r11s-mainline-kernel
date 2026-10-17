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
run 'echo Q1; dmesg | grep -v "Duplicate PDT" | head -120; echo Q2' 8
run 'echo Q3; dmesg | grep -v "Duplicate PDT" | sed -n "121,260p"; echo Q4' 8
run 'echo Q5; cat /sys/bus/rmi4/devices/rmi4-00.fn12/../input/input0/modalias; cat /sys/class/input/event0/device/uevent 2>&1; echo Q6' 2
sleep 1
kill $RXPID 2>/dev/null
echo "[done] $(date +%T) -> $LOG"
