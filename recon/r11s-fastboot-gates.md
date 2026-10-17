# Oppo R11s — bootloader / `fastboot boot` 只读取证门禁

> **状态：未取证。** 不把任何通用 fastboot 变量、同 SoC 设备或 agent 搜索结论当作本机能力证明。
> **范围：**仅记录后续需要取得的原始证据；不包含执行命令，不构成连接、临时启动或刷写授权。
> **安全边界：**不改动手机，不解锁、不写分区、不使用 9008/EDL 自定义刷写；9008 仅为原厂恢复路径。

---

## 1. 已知与未知

项目目前仅记录以下用户提供约束：设备**可以解锁**、可进入 Qualcomm 9008、但 9008 不可刷写自定义固件。

这不证明下列任何一项：

- 设备已经处于 unlocked 状态；
- 标准 Android fastboot 一定存在；
- bootloader 暴露某个特定 `getvar` 键；
- `fastboot boot` 命令已实现；
- bootloader 会接受未签名或任意格式的临时启动镜像。

## 2. 后续唯一可接受的证据

只有以下两类材料可以确认 bootloader 行为：

1. **针对实际设备、只读采集的原始 bootloader 协议输出**，并保留完整原文、时间、设备型号/固件版本；或
2. **相同型号与相同 bootloader 版本的可审计源码/二进制分析证据**，能明确定位命令处理器、接受条件及镜像格式。

即使 bootloader 支持 `getvar`，不同 OEM 对变量名和值的实现也不同。特别是 `flashable:boot` 并非一个可跨设备推导 `fastboot boot` 成功与否的标准保证；unlock 状态也不能独自证明临时启动路径存在。

## 3. 将来评审所需的最小证据包

在任何涉及临时启动、构建或镜像设计的讨论前，先收集并归档：

- 精确型号、地区 SKU、ColorOS build 与 bootloader 版本；
- bootloader 可接受的只读查询响应；
- 原厂 boot/recovery/dtbo（若存在）及分区表的 hash 和解析结果；
- boot image header、签名/verified boot 关系、cmdline、DTB/DTBO 布局；
- 原厂可恢复路径的证据。

取得这些材料后，也仍须在任何设备连接、临时加载或写入前单独取得当次明确许可。

## 4. 参考

- AOSP fastboot 源码与协议实现：<https://android.googlesource.com/platform/system/core/+/refs/heads/main/fastboot/>
- AOSP Android Verified Boot 概述：<https://source.android.com/docs/security/features/verifiedboot>
- 项目审计结论：[`FINAL_RESEARCH_REPORT.md`](FINAL_RESEARCH_REPORT.md)
