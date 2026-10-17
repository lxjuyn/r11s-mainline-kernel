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
run 'echo M1; ls /sys/bus/rmi4/drivers/ 2>&1; echo M2' 2
run 'echo M3; grep -iE "f12|rmi4" /proc/modules 2>&1; ls /lib/modules/*/kernel/drivers/input/rmi4 2>&1; echo M4' 2
run 'echo M5; dmesg | grep -iE "f12|2d sensor|input|probe" | grep -iv "duplicate" | tail -30; echo M6' 3
run 'echo M7; ls /sys/bus/rmi4/devices/rmi4-00.fn12/ 2>&1; cat /sys/bus/rmi4/devices/rmi4-00.fn12/modalias 2>&1; echo M8' 2
run 'echo M9; cat /sys/bus/rmi4/devices/rmi4-00.fn12/driver_override 2>&1; echo MA' 2
sleep 1
kill $RXPID 2>/dev/null
echo "[done] $(date +%T) -> $LOG"
