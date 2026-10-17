# USB-First Ubuntu Initramfs / Gadget 设计说明

**文件类型**: 纯设计文档（不可执行）
**生成时间**: 2026-07-31
**适用范围**: Oppo R11s (Qualcomm SDM660 / arm64)
**严格边界**: 不改 DTS、不生成 initramfs、不操作设备、不刷写

---

## 一、设计目标

本文档描述在 SDM660 R11s 上，**启动后**通过 USB gadget（DWC3 peripheral 模式）建立调试/网络通道，进而传递 Ubuntu initramfs/rootfs 的纯设计思路。核心问题：

1. DWC3 UDC（`a800000.dwc3`）在内核启动后如何进入 gadget peripheral 模式；
2. 通过 configfs 创建 CDC ACM + CDC ECM/NCM 的最小流程；
3. 哪些步骤依赖内核 Kconfig 选项（编译时确定），哪些依赖用户态（systemd / BusyBox）；
4. 哪些步骤在 **当前阶段绝对不可执行**。

---

## 二、内核层：DWC3 UDC 驱动

### 2.1 硬件地址与实机证据

- 实机只读取证已确认：`/sys/firmware/devicetree/base/soc/ssusb@a800000` 存在，compatible 为 `qcom,dwc-usb3-msm`，子节点 `dwc3@a800000` 的 `maximum-speed = "high-speed"`（仅 USB2 HS）。
- 实机 `/sys/class/udc/` 中列出的设备名为 **`a800000.dwc3`**，状态为 **`configured`**（ADB 实机取证见 `recon/p0_adb_readonly_20260730_033057/adb_dtb_usb_iomem.txt` 第 89-91 行）。
- 该证据是 **SDM660 平台 DWC3 peripheral controller 可用性的强证据**，见 `recon/R11S_17011_DTS_LIVE_DT_MATRIX.md` 第 19 行。

### 2.2 相关 Kconfig 符号链

```
CONFIG_USB_GADGET       (drivers/usb/gadget/Kconfig:17)
  └─ select USB_COMMON
  └─ source "drivers/usb/gadget/udc/Kconfig"    # 注册 peripheral controller 驱动
  └─ source "drivers/usb/gadget/function/Kconfig" # 注册 function 驱动

CONFIG_USB_DWC3         (drivers/usb/dwc3/Kconfig:3)
  └─ depends on (USB || USB_GADGET) && HAS_DMA
  └─ choice: USB_DWC3_GADGET / USB_DWC3_HOST / USB_DWC3_DUAL_ROLE
      └─ default USB_DWC3_DUAL_ROLE if (USB && USB_GADGET)
  └─ config USB_DWC3_QCOM   # drivers/usb/dwc3/dwc3-qcom.c (Qualcomm platform glue)
      └─ depends on ARCH_QCOM || COMPILE_TEST

CONFIG_USB_LIBCOMPOSITE  (drivers/usb/gadget/Kconfig:145)
  └─ select CONFIGFS_FS
  └─ depends on USB_GADGET
  # 生成 libcomposite.ko（composite.c, configfs.c, functions.c, u_f.o, usbstring.o, config.o, epautoconf.o）

CONFIG_USB_CONFIGFS      (drivers/usb/gadget/Kconfig:228)
  └─ select USB_LIBCOMPOSITE

CONFIG_USB_CONFIGFS_ACM  (drivers/usb/gadget/Kconfig:249)
  └─ depends on USB_CONFIGFS && TTY
  └─ select USB_U_SERIAL
  └─ select USB_F_ACM

CONFIG_USB_CONFIGFS_ECM  (drivers/usb/gadget/Kconfig:281)
  └─ depends on USB_CONFIGFS && NET
  └─ select USB_U_ETHER
  └─ select USB_F_ECM

CONFIG_USB_CONFIGFS_NCM  (drivers/usb/gadget/Kconfig:269)
  └─ depends on USB_CONFIGFS && NET
  └─ select USB_U_ETHER
  └─ select USB_F_NCM
```

### 2.3 DWC3 gadget 模块

- `drivers/usb/dwc3/gadget.c` 实现 `struct usb_gadget_ops` 和 `struct usb_udc`（DWC3 gadget 控制器驱动）。
- `drivers/usb/dwc3/dwc3-qcom.c` 是 Qualcomm 平台 glue 层，负责时钟、复位、电源管理以及 DWC3 gadget 初始化的平台绑定。
- 该驱动在 probe 成功后，在 `/sys/class/udc/` 下注册设备，命名格式为 `<addr>.dwc3`（实机确认为 `a800000.dwc3`）。

### 2.4 内核层结论

DWC3 gadget 功能完全由 **内核编译时** 的 Kconfig 决定。一旦内核启动且 `dwc3-qcom` probe 成功，`a800000.dwc3` UDC 就会出现，但 **不自动提供任何 USB gadget 功能**——功能必须由用户态通过 configfs 配置。

---

## 三、Configfs 最小流程（用户态）

### 3.1 前置条件

| 条件 | 何时满足 | 依赖 |
|------|----------|------|
| configfs 挂载 | initramfs 或 rootfs 早期 | 内核需 `CONFIGFS_FS=y` |
| `libcomposite.ko` 可用 | 编译时 `CONFIG_USB_LIBCOMPOSITE=y` | 静态链接或 modprobe |
| function 模块可用 | 编译时对应 `CONFIG_USB_F_*` 选项 | `request_module("usbfunc:xxx")` 自动加载 |
| `/sys/class/udc/a800000.dwc3` 存在 | DWC3 gadget probe 完成后 | 内核启动时序 |

### 3.2 创建 gadget 对象

```
mkdir /sys/kernel/config/usb_gadget/g1
echo 0x05c6 > /sys/kernel/config/usb_gadget/g1/idVendor      # Qualcomm VID
echo 0x9025 > /sys/kernel/config/usb_gadget/g1/idProduct      # 示例 PID
mkdir /sys/kernel/config/usb_gadget/g1/strings/0x409
echo "0123456789ABCDEF" > /sys/kernel/config/usb_gadget/g1/strings/0x409/serialnumber
echo "Ubuntu" > /sys/kernel/config/usb_gadget/g1/strings/0x409/manufacturer
echo "Ubuntu Gadget" > /sys/kernel/config/usb_gadget/g1/strings/0x409/product
```

### 3.3 创建配置

```
mkdir /sys/kernel/config/usb_gadget/g1/configs/c.1
echo "CDC-ACM + Ethernet" > /sys/kernel/config/usb_gadget/g1/configs/c.1/strings/0x409/configuration
echo 120 > /sys/kernel/config/usb_gadget/g1/configs/c.1/MaxPower   # 120mA
```

### 3.4 创建函数

```
# CDC-ACM 函数（需要 CONFIG_USB_CONFIGFS_ACM && TTY）
mkdir /sys/kernel/config/usb_gadget/g1/functions/acm.usb0

# CDC-ECM 函数（需要 CONFIG_USB_CONFIGFS_ECM && NET）
mkdir /sys/kernel/config/usb_gadget/g1/functions/ecm.usb0

# 或 CDC-NCM 函数（需要 CONFIG_USB_CONFIGFS_NCM && NET，性能更好）
# mkdir /sys/kernel/config/usb_gadget/g1/functions/ncm.usb0
```

### 3.5 关联函数到配置

```
ln -s /sys/kernel/config/usb_gadget/g1/functions/acm.usb0 /sys/kernel/config/usb_gadget/g1/configs/c.1
ln -s /sys/kernel/config/usb_gadget/g1/functions/ecm.usb0 /sys/kernel/config/usb_gadget/g1/configs/c.1
```

### 3.6 绑定 UDC（激活 gadget）

```
# 列出可用 UDC
cat /sys/class/udc/
# 输出: a800000.dwc3

# 绑定
echo a800000.dwc3 > /sys/kernel/config/usb_gadget/g1/UDC
```

**只有在执行最后一步后，DWC3 硬件才真正对主机端产生 USB 枚举响应。** PC 端将出现：
- `cdc-acm` 驱动匹配 `acm.usb0` --> `/dev/ttyACM0`
- `cdc_ether` 或 `usbnet` 驱动匹配 `ecm.usb0` --> `usb0` 网络接口

---

## 四、Function 模块的自动加载机制

### 4.1 request_module 链

```
configfs.c 中 mkdir functions/<name>.<instance>
    └─ configfs_mkdir() → configfs_create_dir() → gadget_configfs_mkdir()
        └─ request_module("usbfunc:%s", name)   ← drivers/usb/gadget/functions.c:50
            └─ modprobe 自动加载 usb_f_acm.ko / usb_f_ecm.ko / usb_f_ncm.ko
```

### 4.2 模块别名

`DECLARE_USB_FUNCTION_INIT` 宏（`include/linux/usb/composite.h:610`）在模块中注册 `MODULE_ALIAS("usbfunc:<name>")`，使 `request_module("usbfunc:acm")` 自动加载对应的 `usb_f_acm.ko`。

### 4.3 各 function 的内核构建产物

| Function | Kconfig | 内核 module 名 | 需要的内核子选项 |
|----------|---------|---------------|-----------------|
| CDC-ACM | `CONFIG_USB_F_ACM` | `usb_f_acm.ko` | `CONFIG_USB_U_SERIAL`, `CONFIG_TTY` |
| CDC-ECM | `CONFIG_USB_F_ECM` | `usb_f_ecm.ko` | `CONFIG_USB_U_ETHER`, `CONFIG_NET` |
| CDC-NCM | `CONFIG_USB_F_NCM` | `usb_f_ncm.ko` | `CONFIG_USB_U_ETHER`, `CONFIG_NET`, `CONFIG_CRC32` |
| RNDIS | `CONFIG_USB_F_RNDIS` | `usb_f_rndis.ko` | `CONFIG_USB_U_ETHER`, `CONFIG_NET`, `CONFIG_CRC32` |
| Serial | `CONFIG_USB_F_SERIAL` | `usb_f_serial.ko` | `CONFIG_USB_U_SERIAL`, `CONFIG_TTY` |

> **注意**：上述 `.ko` 文件由 `drivers/usb/gadget/function/Makefile` 中的 `obj-$(CONFIG_USB_F_*)` 条目构建，产物位于 `drivers/usb/gadget/function/`。

### 4.4 Ethernet 共享链路层

`CONFIG_USB_U_ETHER` 对应的 `u_ether.c` 提供 `gether_setup_name()` 等共享函数，被 `f_ecm.c` 和 `f_ncm.c` 共用。该模块名是 `u_ether.ko`（在 `drivers/usb/gadget/function/` 中）。

---

## 五、用户态需求：systemd vs BusyBox

### 5.1 仅依赖 BusyBox 可完成的步骤

以下 configfs 操作全部是 **文件读写 + 符号链接创建**，BusyBox 提供的所有工具均能满足：

| 操作 | BusyBox applet |
|------|---------------|
| `mkdir` | `busybox mkdir` |
| `echo ... > file` | shell redirect（shell 内建）|
| `ln -s` | `busybox ln -s` |
| `cat /sys/class/udc/` | `busybox cat` |
| `modprobe usb_f_acm` | `busybox modprobe`（若 BusyBox 有 modprobe 支持）或 `insmod` |
| 挂载 configfs | `busybox mount -t configfs none /sys/kernel/config` |

**结论**：CDC-ACM + ECM/NCM 的 configfs 配置流程 **不需要 systemd**，任何提供基本 shell 和 sysfs/configfs 访问的 initramfs 都可以完成。

### 5.2 systemd 可提供的额外能力

如果 initramfs 或 rootfs 使用 systemd：

| 能力 | 说明 |
|------|------|
| `systemd-udevd` | 在 UDC 出现时自动触发规则，自动挂载 configfs 并配置 gadget |
| `systemd-networkd` | 在 `usb0` 网络接口出现后自动配置 IP（DHCP/static） |
| `systemd-serial-getty` | 在 `/dev/ttyACM0` 上启动登录 shell |
| `systemd-tmpfiles` | 清理 `/sys/kernel/config/usb_gadget/` 下残留配置 |
| `systemd-mount` | 自动挂载 configfs（如果 fstab 配置）|

**结论**：systemd 不是必需的。最小化场景下 BusyBox shell 脚本即可完成全部 gadget 配置。

### 5.3 initramfs 中推荐的最小用户态

```
# 最简 initramfs 脚本示例（伪代码，非实际可执行文件）
mount -t configfs configfs /sys/kernel/config
mount -t sysfs sysfs /sys

# 等待 DWC3 gadget probe 完成（轮询）
while [ ! -d /sys/class/udc/a800000.dwc3 ]; do sleep 1; done

# 创建 gadget
mkdir /sys/kernel/config/usb_gadget/g1
echo 0x05c6 > g1/idVendor
echo 0x9025 > g1/idProduct
mkdir g1/strings/0x409
echo "0123456789ABCDEF" > g1/strings/0x409/serialnumber
echo "Ubuntu" > g1/strings/0x409/manufacturer
echo "Ubuntu Gadget" > g1/strings/0x409/product

# 创建配置
mkdir g1/configs/c.1
echo "USB Gadget" > g1/configs/c.1/strings/0x409/configuration
echo 120 > g1/configs/c.1/MaxPower

# 创建函数（触发 request_module 自动加载对应 .ko）
mkdir g1/functions/acm.usb0
mkdir g1/functions/ncm.usb0    # 或 ecm.usb0

# 关联
ln -s g1/functions/acm.usb0 g1/configs/c.1
ln -s g1/functions/ncm.usb0 g1/configs/c.1

# 激活
echo a800000.dwc3 > g1/UDC
```

---

## 六、initramfs 传递 Ubuntu rootfs 的设计考量

### 6.1 USB gadget 作为网络传输通道

通过 CDC-NCM / CDC-ECM 建立的 `usb0` 网络接口，可以用以下方式传递 Ubuntu rootfs：

1. **TFTP**：PC 端运行 TFTP 服务器，R11s 作为客户端下载 rootfs 镜像到 eMMC 或 tmpfs。
2. **USB 网上传输 rootfs**：通过 `dd if=/dev/usb0 > /tmp/rootfs.cpio.gz` 方式接收（需 PC 端配合发送）。
3. **USB gadget 作为 rootfs 存储设备**：添加 `functions/mass_storage.usb0` 并在 PC 端挂载读取。

### 6.2 CDC-ACM 作为早期控制台

在 rootfs 尚未完全挂载之前，`/dev/ttyACM0` 已经存在。可通过该串口传递命令或读取内核日志，但不适合作为 rootfs 传输通道（带宽太低，通常 < 115200 bps）。

### 6.3 推荐优先级

1. **CDC-NCM + USB0 网络**：高带宽（USB2 HS 可达 480 Mbps），可直接用作 rootfs 下载通道；
2. **CDC-ACM**：用于早期调试控制台和 panic 日志；
3. **Mass Storage gadget**：备选，适合一次性刷写。

---

## 七、绝对不能在当前阶段执行的步骤

| 步骤 | 原因 |
|------|------|
| **刷写任何 boot 镜像** | 无完整且 hash 校验的原厂回滚材料 |
| **修改 R11s DTS 并编译** | R11s 精确 DTS 尚未完成取证（PMIC/regulator/extcon 的 phandle 目标未逐项验证） |
| **生成 initramfs/rootfs 并刷入** | 需要完整的 rootfs 方案和验证流程 |
| **通过 fastboot boot 测试** | 尚未确认 R11s bootloader 支持 `fastboot boot` |
| **通过 EDL/9008 刷写** | 9008 只保留为原厂恢复路径，不允许自定义刷写 |
| **尝试 USB-B 座插入** | R11s 是 USB-C 接口，需要确认 role detect（CC 线）后再连接 PC；直接插入可能导致 host/peripheral 角色冲突 |
| **修改 extcon/Type-C 相关 DTS** | extcon 目标 phandle（PM660 SMB2 charger）尚未在 binding 层验证 |

---

## 八、当前阶段唯一允许的操作

1. **只读研究**：继续从上游内核源码中取证 Kconfig、驱动流程、configfs 接口。
2. **文档编写**：本文档即为此类。
3. **实机只读取证**（如有实机连接且用户授权）：
   - `cat /sys/class/udc/` 确认 UDC 名称；
   - `cat /sys/kernel/config/usb_gadget/` 下是否已有残留配置；
   - 从 `/sys/firmware/devicetree/` 读取 USB/PHY/regulator 节点属性。

---

## 九、关键源码文件引用清单

| 文件 | 内容 |
|------|------|
| `drivers/usb/gadget/Kconfig` | `CONFIG_USB_GADGET`、`CONFIG_USB_CONFIGFS_*`、`CONFIG_USB_LIBCOMPOSITE` |
| `drivers/usb/dwc3/Kconfig` | `CONFIG_USB_DWC3`、`CONFIG_USB_DWC3_QCOM`、`CONFIG_USB_DWC3_GADGET` |
| `drivers/usb/gadget/udc/Kconfig` | USB peripheral controller 驱动列表 |
| `drivers/usb/gadget/function/Makefile` | `usb_f_acm.o`、`usb_f_ecm.o`、`usb_f_ncm.o` 等构建规则 |
| `drivers/usb/gadget/configfs.c` | configfs 用户态接口实现（gadget 创建、配置、绑定） |
| `drivers/usb/gadget/composite.c` | USB 复合设备框架 |
| `drivers/usb/gadget/functions.c` | `usb_get_function_instance()` + `request_module()` 链 |
| `drivers/usb/gadget/function/f_acm.c` | CDC-ACM function 实现 + `DECLARE_USB_FUNCTION_INIT` |
| `drivers/usb/gadget/function/f_ecm.c` | CDC-ECM function 实现 |
| `drivers/usb/gadget/function/f_ncm.c` | CDC-NCM function 实现 |
| `drivers/usb/gadget/function/u_ether.c` | Ethernet-over-USB 共享链路层 |
| `drivers/usb/dwc3/gadget.c` | DWC3 peripheral/gadget controller 驱动 |
| `drivers/usb/dwc3/dwc3-qcom.c` | Qualcomm 平台 DWC3 glue 层 |
| `include/linux/usb/composite.h` | `struct usb_function_driver`、`DECLARE_USB_FUNCTION_INIT` 宏 |
| `Documentation/usb/gadget_configfs.rst` | configfs gadget 用法文档 |
| `Documentation/usb/gadget_dwc3.rst` | DWC3 gadget 文档 |

---

## 十、实机取证引用

| 来源 | 关键信息 |
|------|---------|
| `recon/p0_adb_readonly_20260730_033057/adb_dtb_usb_iomem.txt:89-91` | UDC 名 `a800000.dwc3`，状态 `configured` |
| `recon/p0_adb_readonly_20260730_033057/device_tree_live/ssusb_a800000.txt` | DWC3 节点完整属性：compatible、reg、clocks、interrupts、phy |
| `recon/R11S_17011_DTS_LIVE_DT_MATRIX.md:19-23` | DWC3/QUSB2 节点证据矩阵 |
| `recon/usb_gadget_debug_boot_safety.md` | USB gadget 启动安全门禁与 pstore/ramoops 互补关系 |

---

*本文档为纯设计说明，不包含可执行脚本、不可直接用于构建或刷写。任何实际构建、编译、刷写操作须在完成完整证据取证和用户明确授权后进行。*
