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
run 'echo P1; dmesg > /tmp/dm.txt; wc -l /tmp/dm.txt; grep -inE "f12|rmi" /tmp/dm.txt | grep -iv duplicate | head -40; echo P2' 4
run 'echo P3; cat /proc/bus/input/devices | grep -A2 "EV"; echo P4; cat /sys/bus/rmi4/devices/rmi4-00.fn12/of_node 2>&1 | od -c | head -3; echo P5' 2
sleep 1
kill $RXPID 2>/dev/null
echo "[done] $(date +%T) -> $LOG"
