#!/usr/bin/env bash
# 救援 shell 交互器：向 /dev/ttyACM0 发命令并抓输出。
# 用法: acm_cmd.sh "命令" [等待秒数,默认4] [日志文件]
set -u
DEV=/dev/ttyACM0
CMD="$1"
WAIT="${2:-4}"
LOG="${3:-}"
MARK="ZZDONE_$RANDOM$RANDOM"
stty -F "$DEV" 115200 raw -echo
( timeout $((WAIT+3)) cat "$DEV" > /tmp/acm_cmd_raw.log ) &
CAP=$!
sleep 0.3
printf '\n' > "$DEV"
sleep 0.3
printf '%s\n' "$CMD" > "$DEV"
sleep "$WAIT"
printf 'echo %s\n' "$MARK" > "$DEV"
sleep 1.5
wait $CAP 2>/dev/null || true
cat /tmp/acm_cmd_raw.log
[ -n "$LOG" ] && cp /tmp/acm_cmd_raw.log "$LOG"
