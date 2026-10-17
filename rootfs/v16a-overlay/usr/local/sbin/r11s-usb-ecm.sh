#!/bin/sh
# r11s-usb-ecm.sh — R11s configfs ECM USB 网卡（带外 SSH 通道）
# 设备侧 usb0 = 10.42.0.2/24；主机侧把对应 usbX 配成 10.42.0.1/24 后：
#   ssh r11s@10.42.0.2   （口令 r11s）
# 内核依赖：USB_CONFIGFS=y + USB_CONFIGFS_ECM=y（v15b 已确认 =y）
set -e
G=/sys/kernel/config/usb_gadget/r11s-ecm

mountpoint -q /sys/kernel/config || mount -t configfs configfs /sys/kernel/config
[ -d "$G" ] && exit 0   # 幂等：已配置过直接退出

mkdir -p "$G/strings/0x409" "$G/configs/c.1/strings/0x409"
echo 0x18d1 > "$G/idVendor"
echo 0xd005 > "$G/idProduct"
echo r11s-v16a          > "$G/strings/0x409/serialnumber"
echo OPPO               > "$G/strings/0x409/manufacturer"
echo 'R11s ECM net'     > "$G/strings/0x409/product"
echo 'ECM network'      > "$G/configs/c.1/strings/0x409/configuration"
echo 250                > "$G/configs/c.1/MaxPower"

mkdir -p "$G/functions/ecm.usb0"
ln -sf "$G/functions/ecm.usb0" "$G/configs/c.1/"

UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
[ -n "$UDC" ] || { echo "[usb-ecm] no UDC found" >&2; exit 1; }
echo "$UDC" > "$G/UDC"

# 等 usb0 出现后配静态地址
for i in $(seq 1 40); do
    [ -d /sys/class/net/usb0 ] && break
    sleep 0.5
done
if [ -d /sys/class/net/usb0 ]; then
    ip addr add 10.42.0.2/24 dev usb0 2>/dev/null || true
    ip link set usb0 up
    echo "[usb-ecm] usb0 up: 10.42.0.2/24"
else
    echo "[usb-ecm] usb0 never appeared" >&2
    exit 1
fi
