#!/usr/bin/env bash
# 阶段 1 救援 shell 观察器（只读观察，不自动发命令）。
# 刷写并 fastboot reboot 后运行：轮询 lsusb 等待救援 gadget 0x18d1:0xd004，
# 出现后捕获 /dev/ttyACM0 串口输出到日志。
# 用法: tools/r11s_stage1_serial_watch.sh            # 观察 180s
#       printf 'busybox devmem 0x17817000 32 1\n' > /dev/ttyACM0   # 手动喂狗(WDT_RST)
set -u
cd /home/<user>/claude/r11
LOG=out/stage1_watch_$(date +%Y%m%d_%H%M%S).log
echo "[watch] start $(date +%T)，等待 0x18d1:0xd004（最长 180s）" | tee -a "$LOG"
found=""
for i in $(seq 1 180); do
  now=$(date +%T)
  if lsusb | grep -qi '18d1:d004'; then
    echo "[$now] +RESCUE-GADGET 0x18d1:0xd004 出现（t+${i}s）" | tee -a "$LOG"; found=1; break
  fi
  if lsusb | grep -qi '05c6:900e'; then
    echo "[$now] !! 05c6:900e 下载模式（t+${i}s）——启动失败/WDT 咬死" | tee -a "$LOG"
    exit 3
  fi
  sleep 1
done
[ -z "$found" ] && { echo "[watch] 180s 内未出现救援 gadget" | tee -a "$LOG"; exit 1; }
for i in $(seq 1 15); do [ -e /dev/ttyACM0 ] && break; sleep 1; done
[ -e /dev/ttyACM0 ] || { echo "[watch] gadget 在但无 /dev/ttyACM0" | tee -a "$LOG"; exit 2; }
stty -F /dev/ttyACM0 115200 raw -echo
echo "[watch] 捕获 /dev/ttyACM0 → $LOG.serial（Ctrl-C 结束；喂狗见脚本头注释）" | tee -a "$LOG"
cat /dev/ttyACM0 | tee "$LOG.serial"
