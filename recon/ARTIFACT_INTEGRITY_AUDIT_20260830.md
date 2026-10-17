# R11s 成品完整性独立审计（只读）— 2026-08-30

- 审计人：验证代理（任务 #37）
- 范围：/home/<user>/claude/r11；只读，无写操作（本报告为任务允许的唯一新建文件）
- 依据：任务 #37 权威记录逐项核对，实测为准
- 方法：`ls -l` + `sha256sum` 实测；boot 头手工解析（header v1）；归档 `sha256sum -c`；GitHub 公开 API + 资产流式下载哈希比对（不落盘、未使用/未打印任何凭据）

---

## 1. Boot 镜像（大小 + sha256）

| 文件 | 预期大小 | 实测大小 | 预期 sha256(前8) | 实测 sha256 | 结论 |
|---|---|---|---|---|---|
| out/boot_r11s_phase3_integrated_v9.img | 15,081,472 B | 15,081,472 B | c34f1307 | c34f130775e47ba01586b71a0add31c6364073d54012882c43ae0d35a057d1b5 | PASS |
| out/boot_r11s_phase4_rootfs_v10.img | 15,081,472 B | 15,081,472 B | 28773a5c | 28773a5cf8174287572e9043f1581f01f9b06dd2e1318557a71d0fb6a9adbb3c | PASS |
| out/boot_r11s_phase3_audio_v11.img | 15,101,952 B | 15,101,952 B | a07a5ef5 | a07a5ef599ad8a1a07c63b88ef924d46051480f24084451acf27572f62a7c414 | PASS |
| out/boot_r11s_phase3_touch_v8.img（回滚件） | 13,197,312 B | 13,197,312 B | f668cbc2 | f668cbc2e9ddb1c8604c0a36b3ffe8f9a2e98efb981341ebd25e63d4e894790a | PASS |

## 2. rootfs（大小 + sha256）

| 文件 | 预期大小 | 实测大小 | 预期/实测哈希 | 结论 |
|---|---|---|---|---|
| out/r11s_phase4a_rootfs_v3.ext4 | 201,326,592 B | 201,326,592 B | f54772b7de0b69c026cb8cb73e30ca66e95ea664a62734568b080073012d606b（全量一致） | PASS |
| out/r11s_phase4a_rootfs_v2.ext4（回滚件） | — | 201,326,592 B | 3751550238c322dac098b2531ac83d650caa7a41922d8e23a72f01c3203d56c8（前 8 位 37515502 一致） | PASS |
| out/r11s_phase4a_rootfs.ext4（回滚件） | — | 167,772,160 B（160MiB） | 37db33b72b531c9943afeef3e144831496d702b7e84b22468a73e17872ee65f3（前 8 位 37db33b7 一致） | PASS |

## 3. 镜像头抽查（v9 / v10 / v11）

`tools/r11s_bootimg_pack.py` 无 `--inspect` 子命令（仅打包），故手工解析 header v1：

| 项 | v9 | v10 | v11 |
|---|---|---|---|
| magic @0x00 | `ANDROID!` ✓ | `ANDROID!` ✓ | `ANDROID!` ✓ |
| kernel_size | 13,953,214 | 13,953,214（与 v9 逐字节同核，符合"v10 复用 v9 kernel+DTB"） | 13,974,031（新核，符合音频链改动） |
| ramdisk_size | 1,119,232 | 1,122,304 | 1,119,232 |
| header_version | 1 | 1 | 1 |
| page_size | 0x1000 | 0x1000 | 0x1000 |
| cmdline | `console=tty0 console=ttyGS0,115200n8 loglevel=7 rootwait rw log_buf_len=1M`（**无 root=** ✓） | 同左 + `root=/dev/mmcblk1p69`（**含 root=** ✓） | 同 v9（**无 root=** ✓） |
| 大小自洽（Σceil(seg/page)·page = 文件总大小） | 4096+13,955,072+1,122,304 = 15,081,472 ✓ | 同上 ✓ | 4096+13,975,552+1,122,304 = 15,101,952 ✓ |

结论：三镜像头部与既定配方一致。**PASS**

## 4. 归档目录（backups/products/）+ SHA256SUMS 抽验

| 归档目录 | 内容完备（镜像/指路 + SHA256SUMS + README） | `sha256sum -c` 结果 |
|---|---|---|
| products_r11s_phase3_integrated_v9_20260830_033147 | img + dtb + dts + patches + README + SHA256SUMS | 2/2 全过（img 哈希 = c34f1307…） |
| products_r11s_phase4_rootfs_v10_20260830_044715 | img + ramdisk_v10/v9_orig + init_v10.src + README + SHA256SUMS | 4/4 全过 |
| products_r11s_phase3_audio_v11_20260830_055225 | img + Image.gz + config_v11(.diff) + dtb + ramdisk + README + SHA256SUMS | 6/6 全过 |
| products_r11s_phase4a_rootfs_v3_20260830_061807 | README + SHA256SUMS + tree_listing（镜像 >100MB 指路 out/） | out/ 镜像行过（=f54772b7…） |
| products_r11s_phase4a_rootfs_v2_20260830_060453 | README + SHA256SUMS + tree_listing（指路） | 2/2 全过（v2=37515502…，v1=37db33b7…） |
| products_r11s_phase4a_rootfs_20260830_045727（v1） | README + manifest + SHA256SUMS（指路） | 哈希 37db33b7… 与 out/ 实文件实测一致 |

结论：**PASS**（v1 归档 SHA256SUMS 行尾带说明文字，`-c` 不可直接解析，已手工比对哈希，一致）

## 5. GitHub Release（lxjuyn/r11s-mainline-kernel，公开 API 只读）

| Release tag | prerelease | 镜像资产 | 资产大小 | 资产下载哈希比对 |
|---|---|---|---|---|
| stage3-integrated-v9 | ✓ | boot_r11s_phase3_integrated_v9.img + SHA256SUMS | 15,081,472 ✓ | 下载流式哈希 = c34f1307… = 本地 ✓ |
| stage4-rootfs-v10 | ✓ | boot_r11s_phase4_rootfs_v10.img + SHA256SUMS | 15,081,472 ✓ | 下载流式哈希 = 28773a5c… = 本地 ✓ |
| stage3-audio-v11 | ✓ | boot_r11s_phase3_audio_v11.img + SHA256SUMS | 15,101,952 ✓ | 下载流式哈希 = a07a5ef5… = 本地 ✓ |

各 Release 附带的 SHA256SUMS 内容与本地归档 SHA256SUMS 相应条目逐条一致。结论：**PASS**（未打印/未落盘任何凭据；本地适配树 `android_kernel_oppo_sdm660/` remote 为上游源码仓，发布仓为公开仓，走匿名公开 API）

## 6. 文档一致性抽查（实测 ≥3 处）

| # | 位置 | 记录值 | 实测 | 结论 |
|---|---|---|---|---|
| 1 | STATUS.md L206 | v9：15,081,472 B，c34f1307… | 一致 | PASS |
| 2 | STATUS.md L210 | v10：15,081,472 B，28773a5c… | 一致 | PASS |
| 3 | STATUS.md L223 | v11：15,101,952 B，a07a5ef5… | 一致 | PASS |
| 4 | STATUS.md L229 | rootfs_v2：192MiB/201,326,592 B，37515502… | 一致 | PASS |
| 5 | STATUS.md L247 | rootfs_v3：201,326,592 B，f54772b7…（全量） | 一致 | PASS |
| 6 | HANDOFF_THIRDPARTY_KERNEL_ADAPTATION_20260829.md L95/L99/L105/L113 | v9/v10/v11/rootfs_v3 哈希与大小 | 逐条一致 | PASS |

## 总结论

**全部 6 项审计通过（PASS），未发现任何不一致。**

可刷件确认：
- 主刷镜像 `out/boot_r11s_phase3_audio_v11.img`（a07a5ef5…）与本地归档、GitHub Release 三方哈希一致，头部配方正确（无 root=，走救援/ramdisk 路径）。
- 切根镜像 `out/boot_r11s_phase4_rootfs_v10.img`（28773a5c…）cmdline 含 `root=/dev/mmcblk1p69`，与 p69 切根方案配套一致。
- rootfs `out/r11s_phase4a_rootfs_v3.ext4`（f54772b7…）与 v10 切根镜像配对可用；v2/v1 回滚件哈希均在位。
- 回滚链完整：boot 回滚件 touch_v8（f668cbc2…）、rootfs 回滚件 v2/v1 均可用。

无任何会影响刷写步骤的不一致。
