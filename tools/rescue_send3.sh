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
run 'echo N1; dmesg | sed -n "/5\.9/,/6\.5/p" | grep -iE "rmi4|f12|input" | grep -iv "duplicate" | head -60; echo N2' 3
run 'echo N3; dmesg | grep -nE "5\.9[0-9]|6\.0[0-9]|6\.1[0-9]|6\.2[0-9]" | grep -ivE "duplicate|pm8941|gpio-key" | head -50; echo N4' 3
run 'echo N5; cat /sys/bus/rmi4/devices/rmi4-00.fn12/uevent; echo N6' 2
run 'echo N7; cat /sys/bus/rmi4/devices/rmi4-00/input/input0/capabilities/* 2>&1; ls /sys/bus/rmi4/devices/rmi4-00/input/input0/ 2>&1; echo N8' 2
sleep 1
kill $RXPID 2>/dev/null
echo "[done] $(date +%T) -> $LOG"
