# 核心驱动内建可行性 — 实测取证

> Timestamp: 2026-08-09 23:1x
> 来源: workflow wjs5wl9v3 (1 sonnet agent, 76k tokens)。O= 独立构建, 未刷设备。

## 结论: PASS — 余量大

arm64 Image image_size 字段 @offset16 vs ABL 门限 0x3180000 (51,904,512 B):

| 配置 | image_size | 门限余量 | 状态 |
|---|---|---|---|
| 当前 fork 配置, DRM_MSM=n | 0x1ef0000 = 32,440,320 B | 19,464,192 B (18.6 MiB) | PASS |
| DRM_MSM=y | 0x2080000 = 34,078,720 B | 17,825,792 B (17.0 MiB) | PASS |
| DRM_MSM=y + 全 Wi-Fi =y | 0x2340000 = 36,962,304 B | 14,942,208 B (14.2 MiB) | PASS |

- DRM_MSM=y 增加 1,638,400 B (1.56 MiB)
- 全 Wi-Fi 栈增加 2,883,584 B (2.75 MiB)
- 合计 +4,521,984 B (4.31 MiB) over DRM_MSM=n 基线

=> 用户要求"显示/wifi 核心驱动与内核一起进 boot"**可行** (余 14 MiB)。

## 重要前提修正

1. **旧基线 0x30f0000 (余 589KB) 已过时**: 8-1 fork Image (37f611dd, 48.94 MiB) 由旧大配置构建
   (products_r11s_ubuntu_mainline_20260801_0155/config, LOCALVERSION="", DEBUG_INFO_REDUCED)。
   **当前** fork .config (LOCALVERSION="-sdm660", DWARF5, binder) 产出小得多 (~32MB)。
2. **测试用内核是旧配置**: 两次刷写测试 (fork 候选 + crash-capture) 都用 48.94 MiB 旧内核,
   与当前配置差异大 -> 新测试假说: 大内核 vs 小内核可能影响早期崩溃。
3. **共享树卫生问题**: fork .config 被其他 agent 改过 (DRM_MSM 22:09 被翻 =y, wifi 多次在 =m/=y 间变)。
   构建目录 Image 被并发构建覆盖 (22:39, 0x2080000)。共享树状态不可复现, 需重建干净基线再测。

## 产物

- build/msm_y_probe/Image_drm_msm_y (DRM_MSM=y, 33,526,272 B)
- build/wifi_y_probe/arch/arm64/boot/Image (DRM_MSM=y+wifi=y, 36,413,952 B, image_size 0x2340000)
- 各自 .config / build log 在 probe 目录

## Wi-Fi 内建的关键依赖链 (非一行翻转)

- ATH10K_SNOC=y <- ATH10K=y <- MAC80211=y <- CFG80211=y <- RFKILL=y
- QCOM_WCNSS_PIL=y <- QCOM_SYSMON=y <- QCOM_RPROC_COMMON=y
- QCOM_WCNSS_CTRL=y / POWER_SEQUENCING_QCOM_WCN=y (RPMSG=y 已具备)
- QCOM_QMI_HELPERS 被 select
