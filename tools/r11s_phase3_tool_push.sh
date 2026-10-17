#!/usr/bin/env bash
# 通用裸工具串口推送（只读取证）：把本地 b64 文件经 /dev/ttyACM0 推到板端并解码运行。
# 用法: r11s_phase3_tool_push.sh <本地.b64> <远端可执行名> <b64文件md5> [运行参数...]
set -u
B64=$1
RNAME=$2
EXPECT_MD5=$3
shift 3
RUNARGS="$*"
DEV=/dev/ttyACM0
OUT=/home/<user>/claude/r11/out/phase3_toolpush_$(date +%Y%m%d_%H%M%S).log
stty -F "$DEV" 115200 raw -echo
cat "$DEV" > "$OUT" &
CATPID=$!
trap 'kill $CATPID 2>/dev/null' EXIT
send() { printf '\n' > "$DEV"; sleep 0.2; printf '%s\n' "$1" > "$DEV"; sleep "${2:-0.14}"; }
transfer() {
  send ": > /root/rb" 0.5
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf '\n' > "$DEV"; sleep 0.05
    printf "printf %%s '%s' >> /root/rb\n" "$line" > "$DEV"
    sleep 0.13
  done < "$B64"
  sleep 0.5
}
for attempt in 1 2 3; do
  echo "[host] transfer attempt $attempt ($B64)"
  transfer
  send "md5sum /root/rb" 2
  sleep 1
  if grep -q "$EXPECT_MD5" "$OUT"; then echo "[host] md5 OK"; break; fi
  echo "[host] md5 mismatch, retry"
done
send "base64 -d /root/rb > /root/$RNAME; chmod +x /root/$RNAME; ls -l /root/$RNAME; echo DECODE_OK_$RNAME" 2
send "/root/$RNAME $RUNARGS 2>&1" 15
send 'echo ==DONE==' 1
sleep 1
kill $CATPID 2>/dev/null
echo "---- captured ----"
sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\[6n//g' "$OUT" | grep -v '^\s*$' | grep -A200 "DECODE_OK_$RNAME" | head -120
echo "---- log: $OUT ----"
