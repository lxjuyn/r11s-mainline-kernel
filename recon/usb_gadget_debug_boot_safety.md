# USB Gadget Debug 与启动安全 — 上游证据笔记

**生成时间**: 2026-07-29
**适用范围**: Oppo R11s (Qualcomm SDM660 / arm64) — 仅提取通用上游事实，不含 MTK/Z1 项目信息
**证据来源**: Linux 内核文档、AOSP 文档、内核源码注释
**严格禁止**: 分析 MT6572/Z1 boot 镜像、转移 MTK 事实、执行任何设备活动/构建/下载/编辑

---

## 一、USB Gadget CDC-ACM / configfs — 发生在 UDC userspace 之后

### 1.1 核心机制

Linux USB gadget 框架（UDC, USB Device Controller）分为内核层与用户态层两个阶段：

- **内核层**: SoC 的 DWC3 (DesignWare USB 3.0) 或类似 UDC 驱动在设备树匹配后 probe，注册 `/sys/class/udc/<udc_name>` 设备。此阶段只完成硬件初始化，尚未建立任何 USB 功能。
- **用户态层**: 通过 `configfs`（`CONFIG_USB_GADGET` + `CONFIG_USB_CONFIGFS_*`）在 `/sys/kernel/config/usb_gadget/` 中配置 VID/PID、配置（configuration）、字符串描述符、功能（function），然后将 UDC 绑定到配置：
  ```
  echo <udc_name> > /sys/kernel/config/usb_gadget/g1/UDC
  ```
  **只有在这一步之后，内核才响应主机端的枚举、配置、接口请求。**

> **来源**:
> - `Documentation/usb/configfs_gadget.rst` (内核源码)
>   - https://www.kernel.org/doc/html/latest/usb/configfs_gadget.html
> - `Documentation/usb/gadget_configfs.rst` (CDC-ACM 专用文档)
>   - https://www.kernel.org/doc/html/latest/usb/gadget_configfs.html
> - `drivers/usb/gadget/configfs.c` — configfs 接口实现
> - `drivers/usb/gadget/function/f_acm.c` — CDC-ACM 功能实现

### 1.2 CDC-ACM 功能的具体流程

```
configfs gadget 对象 g1 ──┬── functions/acm.usb0   → 创建 CDC-ACM 功能
                           ├── configs/c.1           → 配置
                           │   └── strings/0x409     → 语言/字符串
                           └── UDC 绑定              → echo udc > UDC
                                                         ↓
                                              内核枚举 → PC 端产生 /dev/ttyACM0
```

- `f_acm.c` 实现 `usb_control` 回调（CDC 管理端点）和 bulk IN/OUT 端点。
- CDC-ACM 的终端节点在 PC 端由 `cdc-acm` 内核驱动匹配为 `/dev/ttyACM0`。
- **关键时序**: CDC-ACM 通道在 UDC 绑定（`echo <udc> > UDC`）之前**不可用**。这意味着：
  - DWC3 probe 完成 → UDC 出现在 sysfs → 用户态通过 configfs 创建 ACM function → 绑定 UDC → PC 端出现 `/dev/ttyACM0`
  - 如果 DWC3 probe 之前内核崩溃（早期驱动 bug、PHY/时钟/电源初始化失败），CDC-ACM 永远无法建立。

### 1.3 对用户 R11s 项目的影响

- R11s 物理 TTL/UART 难以引出 → **主要调试通道是 USB gadget CDC-ACM**。
- 但 USB gadget **不能覆盖 DWC3 probe 之前的早期崩溃**。
- 需要并行部署 pstore/ramoops 等不依赖 USB 的早期证据路径（见下文）。

---

## 二、ramoops / pstore — 需要已知保留内存

### 2.1 核心概念

pstore (persistent store) 是内核中的持久化日志子系统，ramoops 是其"ram console"后端：

- **ramoops** 将内核崩溃/panic 的 console 输出、dmesg、ftrace 等写入一块**预先分配的物理连续 RAM 区域**，即使系统重启也不会丢失（因为内存未清零）。
- 这块内存**必须在设备树中以 `reserved-memory` 节点声明**，确保内核分配阶段不会将其交给伙伴分配器。

### 2.2 关键文档

> **来源**:
> - `Documentation/admin-guide/sysctl/pstore.rst`
>   - https://www.kernel.org/doc/html/latest/admin-guide/sysctl/pstore.html
> - `Documentation/ABI/testing/sysfs-class-pstore`
>   - https://www.kernel.org/doc/html/latest/ABI/testing/sysfs-class-pstore.html
> - `Documentation/core-api/pstore.rst`
>   - https://www.kernel.org/doc/html/latest/core-api/pstore.html
> - 内核源码 `drivers/misc/pstore/ram.c` — ramoops 实现

### 2.3 设备树保留内存格式

下面仅为**语法结构示例**，地址和大小为占位值，绝不可用于 R11s：

```dts
reserved-memory {
    ramoops@<verified-address> {
        compatible = "ramoops";
        reg = <0x0 VERIFIED_ADDRESS 0x0 VERIFIED_SIZE>;
        record-size = <VERIFIED_RECORD_SIZE>;
        console-size = <VERIFIED_CONSOLE_SIZE>;
    };
};
```

- `compatible = "ramoops"` 与 `reg` 是该绑定的关键属性；`record-size`、`console-size`、`ftrace-size`、`pmsg-size` 中至少须有一个非零。
- 节点应位于 `reserved-memory` 下，区域必须在内核接管普通内存前保留，且不得与 R11s 的 modem/DSP/TEE/bootloader 等区域重叠。
- **R11s 的地址、大小、映射属性与记录尺寸尚未取证。**只能从 R11s 原厂 DTB/DTBO、下游 DTS 或实机只读内存布局导出，不能使用示例数字或其它手机的值。

### 2.4 对用户 R11s 项目的含义

- 必须在 R11s 上游 DTS（`sdm660-xiaomi-lavender.dts`）中找到已有的 `reserved-memory` 节点，确认是否有可用于 ramoops 的预留。
- 如果上游 DTS 中没有 ramoops 节点，需要**基于 SDM660 平台已知可用内存布局**添加，而非从 MTK 项目复制任何保留内存参数。
- 读取 pstore 数据：
  ```
  cat /sys/fs/pstore/console-ramoops    # kernel panic 前的 console 输出
  cat /sys/fs/pstore/dmesg-ramoops-0     # dmesg 日志
  ```

---

## 三、安全研究门禁：已解锁 + 9008 已知事实

### 3.1 已确认事实

根据项目 `CLAUDE.md` 和 `STATUS.md` 的记录：

1. **设备可解锁**；当前项目没有将其升级为“已实测标准 fastboot 可用”或“已实测 `fastboot boot` 可用”。
2. **设备可进入 Qualcomm 9008 (EDL) 模式**。
3. **9008 模式不能刷写自定义固件**；该接口只保留为原厂恢复/救援路径。

### 3.2 安全边界

> **来源**:
> - Qualcomm EDL 通用说明: https://wiki.miuixiaozhu.com/EDL
> - AOSP fastboot 文档: https://developer.android.com/studio/command-line/fastboot
>   - https://developer.android.com/studio/command-line/fastboot#booting_an_image
> - Linux USB gadget 驱动框架文档:
>   - https://www.kernel.org/doc/html/latest/usb/gadget.html
>   - https://www.kernel.org/doc/html/latest/usb/gadget_dwc3.html (DWC3 特定)

以下行为**严格禁止**:

| 禁止行为 | 原因 |
|---------|------|
| 尝试绕过 EDL 认证/签名验证 | 安全违规，且项目规则明确禁止 |
| 使用 EDL/9008 刷写自定义 firmware | 不可用 + 被规则禁止 |
| 使用 EDL 下载漏洞利用或 exploit | 违反研究门禁 |
| 将 MTK/Z1 项目的任何 boot 参数、镜像格式、预加载器行为当作 R11s 事实 | R11s 是 SDM660/arm64，启动链完全不同（LK → APQ → RPM → Linux，非 MTK Preloader+LK 链） |

### 3.3 允许的只读研究范围

- 读取 `/sys/` 和 `/proc/` 中不影响运行状态的只读信息。
- 在用户明确授权连接设备后，使用实际存在的标准 fastboot `getvar`/OEM 查询命令读取 bootloader 信息；命令集合和值均由 OEM 决定。
- 分析上游 Linux 内核源码中 SDM660 / DWC3 / USB gadget / pstore / ramoops 的驱动实现。
- 分析 upstream DTS (`sdm660.dtsi`, `sdm660-xiaomi-lavender.dts`) 中 USB/PHY/reserved-memory 节点的声明。
- `fastboot boot` 是否支持，必须通过该机 bootloader 的实际协议响应或可审计的同版本 bootloader 源码确认；**不得从 unlock 状态或任意 `getvar` 的推测值推导**。

---

## 四、USB Gadget 与 pstore/ramoops 的互补关系

| 层面 | CDC-ACM USB Gadget | pstore/ramoops |
|------|-------------------|----------------|
| 生效阶段 | UDC probe + configfs 绑定之后 | 内核启动早期（earlyprintk/ramoops 在 `start_kernel` 后不久即注册） |
| 覆盖范围 | `start_kernel` 之后的用户态 + 内核态日志 | 整个内核启动过程 + panic 前后 |
| 依赖条件 | USB PHY 初始化成功、PC 端有主机驱动 | 保留内存区域已分配且可用 |
| 无法覆盖 | DWC3 probe 之前的崩溃 | 系统完全卡死在 RAM 写入之前 |

**结论**: 对于 R11s（无物理 UART），**USB gadget CDC-ACM 是主要的调试通道，但 pstore/ramoops 是必须并行的早期证据路径**。两者互为补充，缺一不可。

---

*本笔记仅记录通用上游事实，不对 R11s 设备做任何分析、构建、修改或设备活动。*
