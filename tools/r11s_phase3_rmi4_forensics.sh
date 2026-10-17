#!/usr/bin/env bash
# 阶段 3 rmi4 只读取证（经 /dev/ttyACM0 救援 shell，只发只读命令）。
set -u
DEV=/dev/ttyACM0
OUT=/home/<user>/claude/r11/out/phase3_rmi4_forensics_$(date +%Y%m%d_%H%M%S).log
stty -F "$DEV" 115200 raw -echo
# 后台捕获器
cat "$DEV" > "$OUT" &
CATPID=$!
trap 'kill $CATPID 2>/dev/null' EXIT
send() {
  printf '\n' > "$DEV"; sleep 0.3
  printf '%s\n' "$1" > "$DEV"
  sleep "${2:-2}"
}
send 'echo ==J0==; cat /sys/kernel/debug/pinctrl/1000000.pinctrl/pinmux-pins 2>/dev/null | grep -iE "gpio-(66|67)|42|43" | head' 2
send 'echo ==J1==; cat /sys/kernel/debug/gpio 2>/dev/null | sed -n "60,75p"' 2
send 'echo ==J2==; cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | grep -iE "touch|l8|l10|l17|vdd" | head' 2
send 'echo ==J3==; uptime; cat /proc/interrupts | grep -iE "c175000|i2c" | head -4' 2
send 'echo ==DONE==' 1
sleep 1
kill $CATPID 2>/dev/null
echo "---- captured ----"
sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\[6n//g' "$OUT"
echo "---- log: $OUT ----"
