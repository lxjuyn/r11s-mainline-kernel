#!/usr/bin/env bash
# 阶段 3 v6→v7 F12 取证（经 /dev/ttyACM0 救援 shell，只发只读命令）。
set -u
DEV=/dev/ttyACM0
OUT=/home/<user>/claude/r11/out/phase3_rmi4_f12_forensics_$(date +%Y%m%d_%H%M%S).log
stty -F "$DEV" 115200 raw -echo
cat "$DEV" > "$OUT" &
CATPID=$!
trap 'kill $CATPID 2>/dev/null' EXIT
send() {
  printf '\n' > "$DEV"; sleep 0.3
  printf '%s\n' "$1" > "$DEV"
  sleep "${2:-2}"
}
send 'echo ==A1_DRIVERS==; ls /sys/bus/rmi4/drivers/' 2
send 'echo ==A2_FN12_ATTRS==; for f in /sys/bus/rmi4/devices/rmi4-00.fn12/*; do case "$f" in */subsystem|*/driver|*/power|*/of_node) continue;; esac; printf "%s=" "${f##*/}"; cat "$f" 2>&1 | tr "\n" "," | head -c 200; echo; done' 3
send 'echo ==A3_FN12_LNK==; ls -l /sys/bus/rmi4/devices/rmi4-00.fn12/driver 2>&1; cat /sys/bus/rmi4/devices/rmi4-00.fn12/driver_override 2>&1' 2
send 'echo ==A4_FN01_INPUT==; ls /sys/bus/rmi4/devices/rmi4-00.fn01/; ls /sys/bus/rmi4/devices/rmi4-00/input/ 2>/dev/null; cat /sys/bus/rmi4/devices/rmi4-00/input/input0/name 2>/dev/null' 2
send 'echo ==A5_EVENT0_CAPS==; cat /sys/class/input/event0/device/capabilities/evbit /sys/class/input/event0/device/capabilities/absbit /sys/class/input/event0/device/capabilities/keybit 2>/dev/null; ls -l /sys/class/input/event0/device/driver 2>/dev/null | tail -1' 2
send 'echo ==A6_DMESG==; dmesg | grep -iE "rmi4|f12|f11|input|synaptics" | grep -viE "duplicate pDT entry" | head -70' 4
send 'echo ==A7_PDT==; dmesg | grep -iE "f1[12]" | head -20; cat /proc/interrupts | grep -E "rmi4|msmgpio  6[67]"' 2
send 'echo ==DONE==' 1
sleep 1
kill $CATPID 2>/dev/null
echo "---- captured ----"
sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\[6n//g' "$OUT" | grep -v '^\s*$'
echo "---- log: $OUT ----"
