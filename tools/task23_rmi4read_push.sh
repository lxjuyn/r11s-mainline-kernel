#!/usr/bin/env bash
# 任务 23 取证 2：推送 rmi4read_raw 并只读 PDT/寄存器区（只发只读 I2C 命令）
set -u
DEV=/dev/ttyACM0
EXPECT_MD5=$(md5sum /home/<user>/claude/r11/tools/rmi4read_raw | cut -d' ' -f1)
OUT=/home/<user>/claude/r11/out/task23_rmi4read_$(date +%Y%m%d_%H%M%S).log
stty -F "$DEV" 115200 raw -echo
cat "$DEV" > "$OUT" &
CATPID=$!
trap "kill $CATPID 2>/dev/null" EXIT
send() { printf '\n' > "$DEV"; sleep 0.2; printf '%s\n' "$1" > "$DEV"; sleep "${2:-0.35}"; }
send ": > /root/rdb" 0.5
B64=$(base64 -w0 /home/<user>/claude/r11/tools/rmi4read_raw)
i=0
while [ $i -lt ${#B64} ]; do
  CHUNK="${B64:$i:64}"
  send "printf %s '$CHUNK' >> /root/rdb" 0.12
  i=$((i+64))
done
for attempt in 1 2 3; do
  echo "[host] md5 check attempt $attempt"
  send "md5sum /root/rdb" 2
  sleep 1
  if grep -q "$EXPECT_MD5" "$OUT"; then echo "[host] md5 OK"; break; fi
  echo "[host] md5 mismatch, retry"
done
send "base64 -d /root/rdb > /root/rdr; chmod +x /root/rdr; echo DECODE_OK" 1.5
# 厂商 PDT 区间 0xE9..0xC9 及向下滑动、低端真实寄存器区
send "echo R1; /root/rdr e9 32; echo R1E" 3
send "echo R2; /root/rdr c9 32; echo R2E" 3
send "echo R3; /root/rdr a9 32; echo R3E" 3
send "echo R4; /root/rdr 0 32; echo R4E" 3
send "echo R5; /root/rdr 20 32; echo R5E" 3
send "echo R6; /root/rdr 40 16; echo R6E" 3
send "echo ==DONE==" 1
sleep 1
kill $CATPID 2>/dev/null
echo "---- captured ----"
sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$OUT" | grep -A200 'DECODE_OK' | head -200
echo "---- log: $OUT ----"
