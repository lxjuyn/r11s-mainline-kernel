# R11 项目当前状态

## 已确认（用户提供）

- 项目路径：`/home/<user>/claude/r11`。
- 目标：Oppo R11s 的主线 Linux + Ubuntu arm64 bring-up。
- 设备可解锁。
- 能进入 Qualcomm 9008 / EDL。
- 9008 无法刷写自定义固件；它只作为原厂恢复/救援后路。
- 物理 TTL/UART 难以引出，优先走手机 USB gadget 调试。

## 已完成（主机侧，不碰手机）

- 建立目录：`recon/`、`build/`、`tools/`、`out/`、`backups/`。
- 编写总体审阅指南：`R11S_MAINLINE_UBUNTU_GUIDE.md`。
- 编写项目规则：`CLAUDE.md`。
- 完成调研审计：`recon/FINAL_RESEARCH_REPORT.md` 已将可采纳的通用结论、污染资料和必须实机/原厂只读取证的未知项分开记录。
- 多轮只读调研中有部分 agent/workflow 受上游模型服务错误影响；任何混淆 MTK、R11、R11s 或 R11s Plus 的结果已判定为污染资料，不可采信。

## P0-C 官方 C.19 容器取证（2026-07-30）

- 用户确认 C.19 为官方固件；用户提供的 ColorOS CDN 原始 `.ozip` 已保存于 `backups/factory/R11s_11_C.19_1190_20201031/`。
- 该来源状态是“用户确认 + 官方 CDN 对象一致性”，并不替代包内签名链、payload 内容、回滚或实机兼容性验证。
- CDN HTTP Range 响应给出长度 `2618885608` 与 `x-amz-meta-content-md5=e9aee976b7c4559ae4ca977b727ef117`；本地文件大小与 MD5 均匹配，SHA-256 为 `a65deb2681255d7e16e0a98a11843ebcb31378d722b5687fd835161902b6ac73`。
- 容器头声明 `pre-device=R11s`、`R11s_11_C.19`、`R11s_11.C.19_1190_202010310009`、`google_patch=20200905`，并使用 `OPPOENCRYPT!` 封装。
- 未解密或提取 payload；容器头部以外的对象目录及签名结构尚未独立验证。因此当前不能确认或排除该包中的 `system`、`vendor`、`firmware-update`、`boot`、`recovery`、`vbmeta`、`dtbo` 或任何签名对象。这不能外推实机分区布局、其他包或 AVB 策略。
- Tavily MCP 查询曾仅返回现行通用 OPPO 支持/ColorOS 页面，未取得 R11s/C.19 直接发布页、官方校验值或签名链；未使用替代网页搜索服务。完整签名链、payload 完整性与实机回滚/启动条件仍未证实。
- 已建立 `backups/factory/R11s_11_C.19_1190_20201031/README.md` 与 `SHA256SUMS`；整包和下载取证 metadata 文件已逐项复核。

## P1 上游 SDM660 参考构建（2026-07-30）

- 已从 Torvalds/Linux `master` tarball 建立独立上游源码目录；源码 Makefile 版本为 Linux `7.2-rc5`，tarball SHA-256 为 `a6b7146bd42234ffead41276fbe33f972f3ab0fbdd0a8bec29a62c98952316a1`。
- 已以 `ARCH=arm64`、`CROSS_COMPILE=aarch64-linux-gnu-`、arm64 `defconfig` 编译上游 `qcom/sdm660-xiaomi-lavender.dtb`；DTB SHA-256 为 `d9a272708f0c8e8c7b54bb7a891612dd0f8252888dd03686bf91c7b59ee6a40c`，结构回读通过。
- 构建记录、config 与 SHA-256 清单已归档到 `backups/products/products_p1_upstream_sdm660_lavender_reference_20260730_101950/`。
- 该产物只验证 arm64 工具链和上游 SDM660 公共 DTS 依赖链。它是 Xiaomi lavender / Redmi Note 7 参考 DTB，绝不是 R11s DTS/DTB，未且不得用于 R11s 打包、启动或写入。

## 当前禁止事项

- 不解锁、不刷写、不写分区、不生成可刷镜像；
- 不尝试 EDL/9008 绕过或自定义刷写；
- 不将 R11/R11s Plus/MTK 资料当作 R11s SDM660 事实；
- 未备份原厂资料、未确认 boot image 格式和 fastboot 能力前，不做测试镜像。

## 等待完成的证据

1. 精确 R11s 型号/SoC/firmware build；
2. 可核对的一手 R11s OSS kernel、DTS、defconfig 或原厂 DTB/DTBO；
3. 只读 fastboot 状态与 `fastboot boot` 支持能力；
4. 原厂 boot/recovery/dtbo/分区表的安全备份及 hash；
5. R11s USB DWC3/PHY、regulator、角色检测与 ramoops 的板级证据。

---

# 2026-08-01 整夜实证更新（用户授权的刷写测试）

> 本节记录 2026-08-01 用户在明确授权"自己刷写自己做测试、挂 loop 自监督"后
> 完成的实机/主机实证。仅记录事实，所有 hash 可复核。

## 官方 C.19 OZIP 已解密 + boot.img 提取（P0-C 门禁推进）

- 官方 C.19 `.ozip`（SHA-256 `a65deb26…b6ac73`）已用 pinned `bkerler/oppo_ozip_decrypt`
  （commit `eb93b3f3`）只读解密为 `input.zip`（SHA-256 `198af261…420fd19`），
  原包未改；审计见 `out/P0_C1_OZIP_AUDIT/`。
- 提取官方 `boot.img`（SHA-256 `5949396d14aa8113cbd47e0963fb056f1c5e47c182419be29d681651bc1c0dec`，
  15,500,564 B），静态审计：header v1、kernel 字段 = gzip(Image) + **9 个明文 appended DTB**
  （3,205,896 B），其中 #8 = board-id `0x4273`（17011）；无 ramdisk、无 dtbo、无 vbmeta。
- 官方 boot 的 9 个 DTB 均带 `qcom,msm-id=<0x13d 0>`、`qcom,board-id`、`qcom,pmic-id`。

## 主线产物（全部主机侧构建，hash 可复核）

- 主线 Image（Linux 7.2-rc5 + Ubuntu config）：SHA-256 `23de027d…`，51,128,832 B。
- `sdm660-oppo-r11s.dts`（`linux/arch/arm64/boot/dts/qcom/`）：
  最小 R11s board DTS，仅 USB2 HS peripheral + QUSB2 三轨（L1/L10/L7 实机 phandle 验证）
  + eMMC 控制器 identity；无 extcon/ramoops/HS400/lavender GPIO。
  编译 DTB SHA-256 `a7b109f7…`（49,813 B），全部属性通过上游 binding 审查。
- Ubuntu arm64 rootfs：Noble 24.04.3，~235M，systemd/udev/iproute2/kmod/dhcp 已装，
  架构验证为纯 arm64（103 arm64 + 10 all 包，无 amd64 污染）。
- 最小 initramfs：busybox 静态 arm64 + configfs USB gadget（UDC `a800000.dwc3`），
  cpio.gz SHA-256 `af5bb948…`；`/init` 只解析 `root=`，不猜分区。

## 实机 fastboot 测试（用户授权整夜）

- 设备进入 bootloader：`unlocked=yes`、`secure=yes`、`product=sdm660`、
  boot 分区 64MiB raw、`max-download-size` 512MiB。
- **`fastboot boot` 实测：`FAILED (remote: 'unknown command')`**
  → R11s ABL **不实现 `fastboot boot`**（RAM 引导不可用），只能 flash boot 分区。
- flash 官方 C.19 boot.img 之前的回滚链已备：官方 `5949396d…` + 现有 boot-debug `4ff811c3…`。

## 主线 boot.img 实机测试结果（诊断）

| 镜像 | 内核 | DTB | 结果 |
|---|---|---|---|
| v1（主线 boot.img） | 7.2 | 主线 DTB（无标签） | 回 fastboot |
| v2（注入标签） | 7.2 | 主线 DTB + `qcom,board-id=<8 0 0x4273>` 等 | 回 fastboot |
| Combo A | 7.2 | **官方** DTB 17011 | 回 fastboot |
| **boot-debug**（对照） | 4.19 | 下游 DTB | **正常启动回 Lineage** |

- 结论：flash 路径和 ABL 验证正常（未签名测试镜像可启动）；**问题在主线 7.2 内核与
  R11s ABL 的交互，与 DTB 无关**。
- 最强假设：text_offset（4.19/4.4 = `0x80000`，7.2 = `0x0`）+ 加载地址差异；待 ABL
  源码 workflow（wf-abl-load-address / wf-text-offset-verify）确认。
- 设备当前已恢复 boot-debug.img，正常启动回 Lineage，无损坏。

## 2026-08-01 深夜主线引导诊断

> 本节记录 2026-08-01 深夜对"主线 7.2 内核不被 R11s ABL 引导"问题的
> 系统性归因：6 组失败组合、ABL 加载机制确认、text_offset/code0 假设、
> 待验证的解压 buffer 假设，以及下一步。仅记录已实测/已取证事实。

### 6 组失败组合（全部 `fastboot flash boot` 后回 fastboot，boot-debug 对照正常）

| # | 镜像 | 内核 | DTB | header | 结果 | 排除的变量 |
|---|---|---|---|---|---|---|
| v1 | `out/r11s_ubuntu_mainline_boot.img` | 主线 7.2 | 主线 DTB（无 board-id） | 自打包 | 回 fastboot | 基线 |
| v2 | `out/r11s_ubuntu_mainline_boot_v2.img` | 主线 7.2 | 主线 DTB + 注入 `qcom,board-id=<8 0 0x4273>` | 自打包 | 回 fastboot | board-id 标签（E3） |
| Combo A | `out/comboA_mainline_kernel_official_dtb.img` | 主线 7.2 | **官方 C.19 FDT[3]**（17011，SHA `9199febd…`） | 自打包 | 回 fastboot | **DTB 内容**（官方 DTB + 主线内核也被拒） |
| Combo B | `out/comboB_v3gzip_official_dtb.img` | 主线 Image（`gzip -n -9`，与 boot-debug 相同 gzip 头） | 官方 DTB | 自打包 | 回 fastboot | gzip 头格式（FLG/MTIME） |
| v3 | `out/r11s_ubuntu_mainline_boot_v3_padded.img` | 主线 padded Image（Image 开头移到 0x80000） | 官方 DTB | 自打包 | 回 fastboot | text_offset 位置理论（padding 理论正确但**仍失败**） |
| Combo E | `out/comboE_bdheader_mainline_kernel.img` | 主线 padded kernel | 官方 DTB | **boot-debug 完整 header**（os_version/id 原值） | 回 fastboot | `os_version`/`id[32]` header 字段、base 地址 |

- 对照：boot-debug.img（4.19.325-cip，含 ramdisk + 2 FDT）**正常启动回 Lineage**。
- 收敛结论：已排除 DTB 内容（A）、gzip 格式（B）、board-id 标签（v2）、
  header os_version/id 与 base（E）、text_offset padding（v3）；
  **唯一剩余变量 = 主线 7.2 内核本身**。

### ABL 加载机制确认（wf-abl-load-address）

R11s ABL（QcomModulePkg `BootLinux.c`）：
- `KernelLoadAddr = BaseMem() | PcdGet32(KernelLoadAddress = 0x80000)`。
- 将 `Image.gz` 解压到 `KernelLoadAddr` 并跳转此处；
  **忽略 boot header 的 kernel_addr（0x8000）**。
- 解压 buffer 有界：`DeviceTreeLoadAddr - KernelLoadAddr`。

### text_offset / code0 假设

- 4.19（text_offset = `0x80000`）：加载到 0x80000 跳转 → 命中 Image 开头
  `b stext`（code0）→ 正常启动。
- 主线 7.2（text_offset = `0x0`）：加载到 0x80000 跳转 → 落在 Image 中部 → 崩溃。
- v3 padding（Image 开头移到 0x80000）：理论上应正确，**实测仍回 fastboot**，
  故 text_offset 位置假设被削弱，需与解压 buffer 假设一起重新评估。

### 解压 buffer 假设（待 wf-decompression-limit 验证）

- 新假设：ABL 解压 buffer 存在**上限**——主线 Image 约 48.8 MB
  vs 4.19/boot-debug 约 41 MB vs 官方 36 MB；主线可能超限被 ABL 拒绝。
- 机制依据：解压 buffer 有界 `DeviceTreeLoadAddr - KernelLoadAddr`（PCD 0x80000 加载点）。
- 状态：**未验证**，pending `wf-decompression-limit`。

### 下一步（待验证）

1. 验证 ABL 解压大小上限（`wf-decompression-limit`）：确认主线 48.8 MB 是否超限。
2. 试 `CONFIG_EFI_STUB=n` 重新构建主线 Image（排除 EFI stub/头部交互）。
3. 试 sdm660-mainline fork（CPH1707/R11T 同源，含 SDM660 cmdline 过滤等补丁；
   同款 ABL 下已有成功启动先例）。
4. 取得 root 访问后抓取 ABL/bootloader logdump，直接确认加载地址与拒绝点。

### 设备恢复

所有 6 组主线组合（v1/v2/comboA/B/v3/comboE）均已回 fastboot，
设备已恢复 boot-debug.img，正常启动回 Lineage，无损坏。

## 归档

- `backups/products/products_r11s_flash_rollback_20260801_0125/`（回滚链）
- `backups/products/products_r11s_ubuntu_mainline_20260801_0155/`（主线产物）
- `backups/products/products_r11s_ubuntu_mainline_bootimg_20260801_015848/`（boot.img）
- `recon/P2_R11S_MAINLINE_UBUNTU_BRINGUP_STATUS_20260801.md`
- `recon/P2_R11S_MAINLINE_DTS_EVIDENCE_20260801.md`
- `out/test_flash_progress.md`（实时测试日志）
- `out/boot_combo_test_matrix.md`（诊断测试矩阵与证据 E1–E9）


# 2026-08-29 阶段 2 重编完成（第三方内核驱动适配，任务 5 收尾）

- 接力 8/27 中断点：build/r11s_phase2 已有 .config（QCOM_WDT=y）与 r11s DTB，缺 Image.gz。
- 增量续编完成：`make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=build/r11s_phase2 -j16 Image.gz modules`，exit 0、日志零 error；Image 解压后 31,427,072 B（门限 0x3000000 内），782 个模块，vermagic=7.0.14-sdm660-gcc++ 全链一致。
- 打包 `out/boot_r11s_phase2.img`（12,156,928 B，sha256 8a3fa0e8…2d865ec）：头部与第三方原镜像逐字段一致（唯一差异 kernel_size +190KB）；ramdisk 逐字节复用原 ramdisk.cpio；cmdline/os_version 保持第三方原值；静态门禁 PASS（记录见归档）。
- 归档 `backups/products/products_r11s_phase2_20260829_0305/`（镜像+Image.gz+DTB+config+模块清单+门禁日志+SHA256SUMS+README，含回滚与验收标准）。
- 树内 DTS 事实再确认：sdm660-oppo-r11s.dts 自带 qcom,kpss-wdt 节点（U-Boot >80s 实证）与 board-id 0x4273 → 阶段 2 镜像 WDT 应自动喂狗（区别于阶段 1 dtbsurg 镜像需 devmem 手喂）。
- 阶段 1 DTB 手术镜像早已就绪未刷：out/boot_r11s_dtbsurg.img（sha256 94b07f70…）。两镜像齐备，停在任务 6 刷写门禁，等待用户逐次当次确认。
- 阶段 3 预研（只读）：recon/R11S_PANEL_FORENSICS_20260829.md —— R11s 面板 = Samsung SOFEG01_S（1080x2160 cmd 模式，原厂 r11s..dts:16292-16369），与 R11T s6e3fa3 不同源不可照抄；存在 sofeg01_s / ams596w401 双量产变体，需上机取证定夺。
- 回滚链不变：fastboot flash boot boot-debug.img（4ff811c3…）。

# 2026-08-29 实机刷写日：阶段 1/2 双 PASS，任务 6 总闸门通过

- 阶段 1（out/boot_r11s_dtbsurg.img，94b07f70…）首刷 PASS：t+7s 救援 gadget、shell 可用、125s 存活；ABL 面板参数亲证 R11s=SOFEG01_S。
- 阶段 2 首刷（8a3fa0e8…，极简 DTB）FAIL@900e t+52s；v2 复验（7b7dc461…，手术 DTB）PASS：t+13s gadget、2min+ 存活、watchdog0 绑定、/proc/version 确认本地 7.0.14 内核。
- **根因定案**：极简 DTB（211 行主线风）与下游 config 内核不兼容是 900e 根因；手术 DTB 全量下游节点集为兼容底本。
- 设备现状：刷 v2 停在救援 shell（正常）。回滚链不变：fastboot flash boot boot-debug.img。
- 归档：products_r11s_stage1_flash_20260829_1337、products_r11s_phase2v2_flash_20260829_1403。
- 阶段 3 就绪：载体=boot_r11s_phase2_v2 布局（重编内核+全量 DTB），顺序 触摸→显示→音频→WiFi/BT→电池，外设=m，面板驱动以 SOFEG01_S 取证为据。

# 2026-08-29 下午：新镜像取证 + watchdog 手术
- 用户提供 boot-r11s-NEW.img（1e479b79…）= 上游作者 Nan5heng 新构建 7.0.14-sdm660+（GCC 16.1.0）+ 原生 R11s DTB（480 节点，rmi4/wcn3990 在位，无 watchdog，面板仅 s6e3fa3）+ 同契约救援 ramdisk（无模块）。
- 已做 stage-1 同款 watchdog 手术并重打包 out/boot_r11s_NEW_wdtsurg.img（0ca184e4…），门禁全过，待请示刷写。
- 取证与策略见 recon/R11S_NEW_IMAGE_FORENSICS_20260829.md；归档 products_r11s_NEW_wdtsurg_20260829_*。

# 2026-08-30 凌晨：触摸定案 + 四路集成镜像 v9 + 阶段 4（rootfs）全套就绪（待用户授权刷写）

## 触摸：v8 上板定案 + PDT 修复
- v8 上板实证：I2C/传感器/中断全链路完好（用户划屏产生真实中断），唯一故障 = F12 PDT 扫描布局。
- Nick 对照原厂修复：PDT_END 0x05→0xd0、10 页扫描上限、幽灵函数白名单、原厂布局回退。
- 原厂面板逆向（用户指定方法）：原厂 boot 内核段无面板 compatible（MDSS 为 DT 数据驱动），权威集合取 17011 编译链 = sofeg01_s（已支持）+ ams596w401（新移植 538 行驱动 + DTB 节点，优雅失败不回退显示链）。

## 四路集成镜像 v9（阶段 3 集成）
- 产物：out/boot_r11s_phase3_integrated_v9.img（15,081,472 B，sha256 c34f1307…），Release `stage3-integrated-v9` 已发；树内提交 d947f542d 已推送。
- 内容 = 触摸 PDT 修复 + 音频链源码（AK4376/MAX98927L/glue 机器驱动；声卡因 DTB 下游绑定预期不注册）+ WiFi/蓝牙 config（WCN3990，零源码改动）+ 电池/充电（qcom_smbx 限流钳位 1.5A，DTB battery@4000 节点已打开）。
- 固件盘点（Sarah）：backups/firmware_inventory_r11s_20260830_043151/，部署集 110 文件 83MiB（补齐此前缺失的 adsp/cdsp mdt 段、venus、fastrpc 库）；定案固件走 rootfs /lib/firmware，不进 ramdisk（超 64MB boot 上限）。
- rootfs 方案：recon/PHASE4_ROOTFS_PLAN_20260830.md；目标分区 /dev/mmcblk1p69（userdata ~46.3GiB）；写入路径 = 救援 shell 拉 configfs mass_storage LUN + 主机 dd（脚本 tools/r11s_phase4_emmc_setup.sh，默认干跑）。
- v10 切根镜像（Jack）：out/boot_r11s_phase4_rootfs_v10.img（15,081,472 B，sha256 28773a5c…，Release `stage4-rootfs-v10` 已发）= v9 kernel+DTB 逐字节复用 + 新 /init（支持 root=/dev/mmcblk1p69 挂载切根，任何失败落回救援 shell 防砖）。
- 阶段 4a rootfs 成品（Hunk）：out/r11s_phase4a_rootfs.ext4（160MiB，sha256 37db33b7…）= Alpine 3.24.1 minirootfs + 110 固件文件（sha256 全过）+ gadget 自拉起（18d1:d004/ttyGS0）+ getty 重生 + r11s-diag 巡检；归档 backups/products/products_r11s_phase4a_rootfs_20260830_045727/。

## 待办链（待用户授权，逐次当次确认）
1. 刷 v9 验收四路（触摸应出坐标）；
2. 刷 v10（p69 未格式化时行为同 v9）；
3. 授权格式化 p69 + 写 rootfs（需用户当次确认，脚本双重确认）；
4. 回滚链：v10→v9→v8→…→boot-debug.img（4ff811c3…）。
- 设备当前状态：停在 fastboot（18d1:d00d），boot 链完好。

# 2026-08-30 清晨（第二轮）：v11 音频候选镜像 + rootfs v2 模块层（纯主机侧，待授权刷写）

## v11 音频候选（候选件，未刷）
- 产物：out/boot_r11s_phase3_audio_v11.img（15,101,952 B，sha256 a07a5ef5…）= 音频链 8 项转 =y（无模块依赖）+ 候选 DTB 两行修复 + glue 机器驱动禁用 + TFA9890 驱动树内已有。
- 构建源：build/r11s_phase2（与 v9/v10 同源），vermagic 7.0.14-sdm660-gcc++。

## rootfs v2：补 /lib/modules 模块层（任务 #34）
- 背景：v1 rootfs 无 /lib/modules，未来任何 =m 驱动（USB offload、更多外设）将失效；本轮把 v11 构建的全量模块层补入。纯主机侧：复制 rootfs/phase4a_stage 到 rootfs/phase4a_v2_work 操作，modules_install 落独立目录 build/r11s_phase2_modstage 再搬，适配树与原暂存树零改动。
- 模块集：681 个 .ko.zst（INSTALL_MOD_STRIP=1 剥调试段：180MiB→12MiB），目录 /lib/modules/7.0.14-sdm660-gcc++（drivers 537/net 85/fs 25/crypto 15/sound 8/lib 7/arch 4）；实测 vermagic `7.0.14-sdm660-gcc++ SMP preempt mod_unload aarch64` 与 v11 内核对应；depmod 已在主机侧打包时完成（设备侧无需重跑，结论已记录）；modules_install 未带出固件，与 rootfs 自带 /lib/firmware（110 文件）无重复。
- 新成品：out/r11s_phase4a_rootfs_v2.ext4（192MiB，201,326,592 B，sha256 37515502…），ext4 特性与 v1 一致（has_journal+metadata_csum，卷标 r11s-phase4a），余量 36%；e2fsck -fn 全遍干净；只读挂载+debugfs 抽检通过（/lib/modules 与 /lib/firmware 同在、681 个 .ko.zst、/sbin/init 未动 4679B/0755）。
- 旧件原样保留：out/r11s_phase4a_rootfs.ext4（160MiB，sha256 37db33b7…）作回滚件；归档 backups/products/products_r11s_phase4a_rootfs_v2_20260830_060453/（双语 README + SHA256SUMS + 树清单；镜像 >100MB 原位留 out/，归档只指路）。

## 待办链（不变，待用户授权，逐次当次确认）
1. 刷 v11（音频候选，接替 v9 作四路验收件）；
2. 刷 v10（切根镜像）；
3. 授权格式化 p69 + 写 rootfs（用 v2 件，脚本双重确认）；
4. 回滚链不变：v10→v9→v8→…→boot-debug.img（4ff811c3…）；rootfs 回滚件 = v1。
- 设备当前状态不变：停在 fastboot（18d1:d00d），boot 链完好。

# 2026-08-30 清晨（第三轮）：rootfs v3 = v2 + WiFi userspace 四件套（纯主机侧，主机侧准备全部完成，待授权刷写）

## rootfs v3（任务 #36）
- 做法：复制 rootfs/phase4a_v2_work 为 rootfs/phase4a_v3_work（v2 树保留未动），按任务 #35 NOTE §五并入四件套：
  - 四二进制（全静态 aarch64，stripped，qemu 冒烟已过）入 /sbin/（0755 root:root）：rmtfs（2783799c…）、pd-mapper（8b14ba96…）、qrtr-lookup（608edb48…）、qrtr-cfg（5bd65d3a…），哈希与来源目录备份一致；
  - /sbin/init 追加启动段（插在固件在位检查后、getty 循环前；原 gadget/getty 逻辑逐字节未动）：mkdir -p /var/lib/rmtfs → pd-mapper 先 → rmtfs -o /var/lib/rmtfs -v 后（日志落 /var/log/rmtfs.log），均后台；
  - 预建 /var/lib/rmtfs（后续真机 EFS/board data 取证件放入）与 /var/log。
- 隐私检查（红线，实测）：四二进制 strings 无本机用户名/路径/凭据；工作树全量文本扫描干净（仅证书束误命中）；passwd/shadow 无密码哈希。
- 新成品：out/r11s_phase4a_rootfs_v3.ext4（192MiB，201,326,592 B，sha256 f54772b7de0b69c026cb8cb73e30ca66e95ea664a62734568b080073012d606b），ext4（has_journal+metadata_csum，卷标 r11s-phase4a），余量 35%；e2fsck -fn 全遍干净（1526/49152 文件）；只读挂载抽检通过（四二进制在位 0755 root:root、init 追加段在、/lib/modules 681 个 .ko.zst 与 /lib/firmware 110 文件原样）。
- 归档：backups/products/products_r11s_phase4a_rootfs_v3_20260830_061807/（双语 README + SHA256SUMS + 树清单；镜像 >100MB 原位留 out/）。
- 旧件原样保留：v2（37515502…）、v1（37db33b7…）均为回滚件；phase4a_v2_work 树未动。
- 主机侧准备全部完成：与 v11 内核镜像（boot_r11s_phase3_audio_v11.img）配套的 rootfs 候选件升级为 v3（写 p69 时用 v3 件）。

## 待办链（不变，待用户授权，逐次当次确认）
1. 刷 v11（音频候选，接替 v9 作四路验收件）；
2. 刷 v10（切根镜像）；
3. 授权格式化 p69 + 写 rootfs（用 v3 件，脚本双重确认）；
4. 回滚链不变：v10→v9→v8→…→boot-debug.img（4ff811c3…）；rootfs 回滚件 = v2/v1。
- 设备当前状态不变：停在 fastboot（18d1:d00d），boot 链完好。

# 2026-08-30 清晨（第四轮）：三维评审修复 + v12 镜像（任务 #39，纯主机侧，未触碰设备）

## 评审结论摘要（三维代码评审，对象 = v11 候选代码/配置/打包链）
- 审计 6 项全过：源码合并正确性、构建可复现性、打包布局、DTB 一致性、回滚链、主机侧安全（不触设备）。
- 结论"可刷但需修复项"，三项发现处置如下（全部已落实为主机侧修复）：
  1. **安全**：qcom_smbx 限流钳位丢 4.8A 硬件上限（d947f542d 引入）→ 修复：ceiling = min(4.8A, 电池档案上限)。
  2. **内存安全**：rmi_create_function 注册失败路径双重释放（put_device 已 kfree 后又 kfree）→ 删除多余 kfree。
  3. **顺手项**：rmi_f12 软复位未查返回值 → 已查并在失败时 dev_warn（重试行为不变）；PDT dump 截断条件 `>` → `>=`。
  4. **可复现性缺口**：树内 r11s_defconfig 与实际构建 .config 脱节 → savedefconfig 回写（8092 行→966 行最小等价集），往返对账逐符号一致；关键符号（音频链/面板/电池/充电/无线/调制解调器/RMI4）均 =y，SND_SOC_SDM660_OPPO_R11S 未启用。
  5. **DTB**：候选 DTB 的 panel@1（ams596w401，无 port 节点，与 panel@0 共用 reset GPIO）→ 加 status="disabled" 重编为 dtb_v12.dtb；dtc 往返自检仅多这一行。

## 源码提交（仓库 main，已推送）
- b7015cc53 评审修复（修复 1/2/3，3 文件 +17/-7）
- 08456b1e7 defconfig 回写（修复 4，8092→966 行）

## v12 镜像（= v11 增量：上述全部修复，纯主机侧打包，未刷）
- 文件：out/boot_r11s_phase3_reviewfix_v12.img
- 大小：15,101,952 B (0xe67000)，与 v11 同布局（base 0x80000000 / ramdisk@0x3000000 / hdr v1 / os 0x12000139 / 救援 cmdline 无 root=）
- sha256：c93e00397ae98be09bc72f07779d25acb105142e1b0509e4831d9d8dfa69cc63
- 内核 Image.gz sha256 f50075428c11…（13,907,747 B；解压后 Image 39,174,656 B ≤ 50,331,648 B 门禁 PASS）；vermagic 7.0.14-sdm660-gcc++ 复验通过
- dtb_v12.dtb sha256 39aba9aa3d8d…；ramdisk 沿用 v11 归档救援件（1ad7419650ba…）
- 打包走 tools/r11s_bootimg_pack.py dry-run → write，dry-run 预测哈希与实际一致
- 归档：backups/products/products_r11s_phase3_reviewfix_v12_20260830_063917/（img+Image.gz+config_v12+dtb_v12+ramdisk+README+SHA256SUMS）；DTB 手术材料：backups/source/dtb_v12_surgery_20260830_063453/

## 待办链更新（待用户授权）
1. 刷 v12（接替 v11 作验收件：含全部评审修复）；
2. 刷 v10（切根镜像）；格式化 p69 + 写 rootfs（用 v3 件）；
3. 回滚链更新：v12→v11→v9→v8→…→boot-debug.img（4ff811c3…）；rootfs 回滚件 = v2/v1。
- 设备当前状态不变：停在 fastboot（18d1:d00d），本任务未触碰。

# 2026-08-31：v12 面板 regulator defer 根因调查 + v13 regdiag 镜像（主机侧，未触碰设备）

## 调查背景

v12 实机（用户提供日志 1.txt）显示面板驱动停在：
`[11.750011] mipi-dsi c994000.dsi.0: deferred probe pending: panel-samsung-sofeg01-s: Failed to get regulators`

## 根因调查（两轮，修正版结论）

第一轮假设"RPM glink 整链死亡"被**第二轮静态取证推翻**：

- 1.txt 中 `mipi-dsi c994000.dsi.0` 设备存在 ⟹ DSI host probe 完成 ⟹
  DSI 自身 vdda（PM660 l1）与 PHY vcca（PM660L l1）已解析 ⟹
  **两套 RPM regulators 组均已注册，RPM glink 链是活的**。
- v6 实测（显示打通）：面板三条供电 vddio（PM660L l11）/vdd（PM660 l6）/oledb（SPMI oledb@e000）
  全部解析成功；v5 根因（OLEDB=m 无模块）v6 已修复（=y）。
- v6 与 v12 DTB 面板相关内容**逐字节一致**（完整 diff 仅 4 处：battery@4000 翻 okay、
  panel@1 新增 disabled、lpass-lpi #pinctrl-cells、adsp firmware-name 前缀）。
- v6→v12 config 差异 182 行 = 大量 =m→=y 翻转（音频/无线/电池充电/SPMI 传感器/LPASS/Q6V5），
  全部为 device_initcall 段新增驱动。

**当前最强嫌疑 = 时序回归**：device_initcall 段内 probe 顺序/并发负载被
新增 =y 驱动重排，面板 probe 落在 RPM regulators（PROBE_PREFER_ASYNCHRONOUS）
注册完成之前，且 10s deferred_probe_timeout 窗口内无后续事件触发补 probe 轮。
次嫌疑 = oledb SPMI probe 竞态。均已排除 DTB/phandle 差异可能。

完整推理链与证据：`recon/R11S_PANEL_REGULATOR_DEFER_ROOTCAUSE_20260831.md`（修正版）。

## v13 regdiag 镜像（唯一增量 = 逐条供电 errno 诊断）

- 源码提交：`419244cc3`（已推送 origin/main）：sofeg01_s / ams596w401 驱动在
  `devm_regulator_bulk_get_const()` 失败时对 vddio/vdd/oledb 逐条 `regulator_get()` 并打 `dev_warn`。
- 文件：`out/boot_r11s_phase3_regdiag_v13.img`
- 大小：15,106,048 B (0xe68000)
- sha256：`0d2966a10e8429864e5e337d568d66286a9727f6cb1957b0d7c1fa83fbc02092`
- 内核 Image.gz sha256 `2135d6cb…`（13,911,094 B；解压后 39,174,656 B ≤ 0x3000000 PASS）
- DTB：dtb_v12.dtb（sha256 `39aba9aa3d8d…`）逐字节复用
- ramdisk：ramdisk_v6.cpio（sha256 `1ad7419650ba…`）逐字节复用
- header 逐字段对比 v12：唯一差异 kernel_size +3347 B（诊断代码）
- 归档：`backups/products/products_r11s_phase3_regdiag_v13_20260831_0211/`

## 上板判据（待用户授权刷写）

刷入后在救援 shell 执行：
```
dmesg | grep -iE "supply|oledb|glink|smd|rpm|deferred"
cat /sys/kernel/debug/devices_deferred
ls /sys/bus/rpmsg/devices/
cat /sys/kernel/debug/regulator/regulator_summary
```
预期 `supply vddio/vdd/oledb: <errno>` 逐条日志：
- 三条全 -517 → regulators/oledb 均未就绪（时序回归极端形式）；
- 仅 oledb -517 → SPMI oledb probe 竞态；
- 任一 -19 → phandle 解析失败（静态已排除，防运行时意外）。

若确认时序回归：最快验证 = cmdline 加 `deferred_probe_timeout=30` 重打包 v14。

## 待办链更新（待用户授权）
1. 刷 v13（regdiag，接替 v12 作诊断件）；
2. 根据 errno 结果决定：deferred_probe_timeout=30 验证 / 其他修复；
3. 回滚链更新：v13→v12→v11→v9→…→boot-debug.img（4ff811c3…）。
- 设备当前状态不变：停在 fastboot（18d1:d00d），本任务未触碰。

# 2026-09-01 晚：v13 实机刷写 — 面板 defer 未复现，显示链打通（已定案）

- v13 刷写成功，救援 gadget t+3s 出现（历史最快），shell 可用。
- **面板完全成功**：OLEDB 3.40s 使能 → sofeg01_s 3.75s probe 完成（power mode 0x9e OK）→ fbcon/fb0 3.86–3.95s 就位。v12 的 "Failed to get regulators" defer **未复现**；`/sys/kernel/debug/devices_deferred` 为空；regulator summary 中面板三条供电（oledb/vdd/vddio）全部绑定（ref=1）。
- **结论修正**：v12→v13 唯一差异 = 面板驱动 bulk 失败路径的诊断代码（+3347B）。defer 出现在 v12、消失于 v13，强烈指向**时序竞态**（嫌疑 A 佐证），而非确定性缺陷。诊断代码没有"修"任何东西，只是移动了时序。
- cmdline 取证：ABL 注入参数被树内过滤补丁吃掉首字符（`_oot=`、`_nit=`、`_kip_initramfs`），`mdss_mdp.panel=...sofeg01_s...` 原样保留 → 过滤是选择性黑名单行为。`printk.disable_uart=1` 被注入但实际 console 还是 ttyGS0。
- 新增待办（不阻塞显示）：GPU 固件 `qcom/a530_pm4.fw` 缺失（fbcon OK，GPU 加速缺）；adsp/cdsp `qcom/sdm660/*.mdt` 与 BT `qca/crbtfw21.tlv` 在救援 ramdisk 缺失（rootfs v3 已备，等切根）；触摸 s3508 F12 描述符 I2C -95（老问题）；DPU mdp_clk_src RCG warning（不阻塞）。
- 归档：`backups/products/products_r11s_phase3_regdiag_v13_flash_20260901_2200/`（dmesg 去重 758 行 + raw 捕获 + README + SHA256SUMS）。
- 设备当前状态：**运行 v13 救援 shell**（非 fastboot）。
- 后续建议（待用户决定）：复刷 v12 验证竞态假设（defer 复现=竞态实锤；不复现=一次性 boot 环境）；或直接接受 v13 作显示链基线推进阶段 4。

# 2026-09-02：v14 规划轮 — 联网映射 + 七域子代理并行取证（主机侧，未触碰设备）

> 编排：`AGENT_ORCHESTRATION.md`（用户已选「按问题域切分」+ W=4）。
> Wave 0 联网同 SoC 社区情报 → Wave 1/2/3 七域子代理并行 → Wave 4 Hub 汇总。
> **全程只读取证：未改源码、未打镜像、未刷机。**

## 交付物

- 问题汇总表：`recon/R11S_V14_ISSUE_MATRIX_20260902.md`（七域 30 项）
- 改进方案：`recon/R11S_V14_IMPROVEMENT_PLAN_20260902.md`（v14a/v14b/v15 分批，补丁级定位）
- 合成与刷写预案：`recon/R11S_V14_IMAGE_PLAYBOOK_20260902.md`（**待授权，未执行**）
- 七域档案：`recon/v14_domains/DOMAIN_*.md`
- 账本：`recon/orchestration/LEDGER_v14_20260902.md`

## 联网映射结果（同 SoC 社区 → 本项目）

| 社区结论（佐证级） | 来源 | 映射 |
|---|---|---|
| SDM660 主线：WiFi(WCN3990+ath10k_snoc) ✅ / BT ✅ / Display ✅ / Storage ✅ | jason 移植报告 §3 | 印证本项目缺口在**固件打包**而非主线能力 |
| 原厂 `wlanmdsp.mbn` 1.0.0.533 / htt-ver 3.50 → WiFi 起后 ~350ms fatal error | jason §12.1 | 本项目版本未取证 → A-6 必须先核对 |
| wlanmdsp 与 modem 组件**强耦合**，单换会 modem watchdog timeout | jason §12.1-4 | 若要换必须**整组**替换 |
| WiFi **依赖 modem DSP**，不可禁用 modem | jason §12.2 | v14 必须抓 `remoteproc0`/mss 加载行 |
| QMI 协商需**冷启动**，warm reboot 会致状态不一致 | jason §12.1-6 | 测试流程约束 |
| GPU(Adreno 512) ⚠️ Partial：KMS/fbcon OK，3D 不完整 | jason §3 | 与本项目 G2/G3 固件缺口吻合 |
| 多面板变体 = 一变体一 DTB + kernel 子包（lavender 三子包） | pmaports device-xiaomi-lavender | 印证双面板差距清单 G01 **路线 A** |
| SDM660 声卡上游补丁 v1(2026-02,10 补丁) → v4(2026-05,15 补丁)，**合入状态未证实** | `lwn.net/1058301`、`ratatoskr.run/.../8251534` | 树内已有**本地移植改造版** `sdm660-internal.c`（12.28KB，非上游 271 行原始版），"移植"与"上游合入"须区分表述 |

**联网失败项（已降级为「未取证」，不影响定案）**：postmarketOS wiki（Anubis 反爬拦截）、`github.com/sdm660-mainline`（超时 10s）、`oppo-source` 的 sofeg01 dtsi（GitHub raw 超时）、`sofeg01`/`ams596w401` 公开型号资料（全网零结果）。`node` 不可用 → Web Access skill 的 CDP 路径整体不可用，全程用 `web_search`/`web_fetch`。

## 七域结论摘要

| 域 | 核心结论 |
|---|---|
| 触摸 | 根因 = `rmi_driver.c:887` 零长读（-95）+ `rmi_f12.c:470/480/490` 无上限 defer；占 `deferred_probe_work` 82–96% |
| 显示 | 根因 = `dpu_kms.c:1315` 无条件 `set_rate(ULONG_MAX)` 且返回值未检查 + 顺序早于 `pm_runtime_enable`(:1324) |
| 音频 | 树内已有移植版 `sdm660-internal.c`；但 `CONFIG_SND_SOC_SDM660_OPPO_R11S` **未启用**（.config:4469 not set） |
| WiFi·BT | 供电完整；`ath10k/WCN3990/hw1.0/firmware-5.bin` **缺失**，原厂 mbn 孤立在 `archive/` |
| GPU | 节点**无 supply 属性**；`a530_pm4.fw`/`a530_pfp.fw`/`a512_zap.mbn` **三项全缺** |
| 构建打包 | 15 本地提交中 **7 个未上板验证**；打包脚本默认值与 v13 事实冲突，须显式传参 |
| 文档 | HANDOFF/STATUS **6 处不一致**；仲裁规则「以 STATUS 为准」是单向声明，STATUS 从未声明自己权威 |

## 本轮实证的硬事实

- **v13 ramdisk 谱系**：`v13/ramdisk_v6.cpio` == `v10/ramdisk_v9_orig.cpio` == `1ad7419650ba1aba6fba030daa014312dd431a44eaf65e1f32f3f0e663e9a7d2` → **v13 不含切根 init**（哈希实证）
- **三份 v14 原料 hash 已核验**：Image.gz `2135d6cb…`、dtb_v12.dtb `39aba9aa…`、ramdisk_v10.cpio `d3fc164a…`
- **回滚件 hash 已核验**：`boot-debug.img` `4ff811c3…`、v13 img `0d2966a1…`、rootfs v3 `f54772b7…`

## 文档自纠

- `STATUS.md:286 / :349` 的回滚链**漏了 v10**（唯一切根镜像），已在合成预案补全 7 级链。
- `STATUS.md` 中 6 处「设备当前态」有 5 处已失效且无过期标注；**当前唯一有效的是「运行 v13 救援 shell」**。
- v13 归档 README 称 `devices_deferred` 为空——与实机持续 defer 矛盾（cat 恰好抓到瞬态空档），**不能作为证据**。

## 待办链更新

1. 用户裁决 v14a / v14b 范围；2. **A-6 固件版本核对**（v14 上板前必做）；3. 合成 v14 + 门禁；4. 刷写（**待当次授权**）；5. 格式化 p69 + 写 rootfs v3（**待当次授权**）。
- 回滚链：v14→v13→v12→v11→**v10**→v9→…→boot-debug.img（`4ff811c3…`）。
- 设备当前状态不变：**运行 v13 救援 shell**（非 fastboot）。本任务未触碰。

---

# 2026-09-02（第二更）：v14a/v14b 实刷实测 — 触摸根治、蓝牙首通、DPU 时钟修复

## 刷写记录（用户当次授权；fastboot `9144dacf`，刷写/重启/测试均实测完成）

| 镜像 | sha256 | 内核 commit | 结果 |
|---|---|---|---|
| v14a | `eb7f16d5e211…409f9` | `f901d1b99`（#13） | ✅ 稳定 46s+ 无崩溃 |
| v14b | `5d1e2c8b42f7…bbd5` | `f901d1b99`+`8f1116321`（#14） | ✅ 稳定，**当前在机** |

## 实测对比（v13 基线 → v14a → v14b）

| 项 | v13 | v14a | v14b |
|---|---|---|---|
| rmi4 无限 defer 循环 | 永动 704–727ms/轮 | ✅ **3 轮封顶**（1/3→2/3→giving up），`COUNT_DEFER=2`，放弃后无空指针崩溃（A-2 的 clear_irq_bits 防护生效） | ✅ 本轮 0 defer |
| 触摸输入设备 | ❌ 不注册 | ❌（当轮描述符读回 `02 00 00 00` 不合法→-22） | ✅ **`Synaptics s3508` → event0 注册**；F12 三描述符一次全过：Query `20 00 00 1a` / Control `1a 80 01 19` / Data `19 0e 80 01` |
| 蓝牙 | ❌ crbtfw21 -2 | ✅ **`QCA setup on UART is completed`**（A-8：ramdisk 补 qca 固件） | ✅ 同 |
| mdp_clk_src RCG | ❌ `rcg didn't update` | ❌ 仍在 | ✅ **消失**（B-1 `rpm_get_sync` 前置 + B-2 `CLK_OPS_PARENT_ENABLE`），set_rate 无错误输出 |
| a530 微码 | ❌ -2 | ❌ -2（v14a 不带） | ✅ `loaded qcom/a530_pm4.fw & a530_pfp.fw from new location`（B-5） |
| GPU 3D | ❌ | ❌ | ❌ 错误链推进到 `a512_zap.mbn` 缺失 → gpu hw init -2（**绑定与 card0 不受影响**；v15 项） |
| 显示 | ✅ fbcon | ✅ card0 + renderD128 + msmdrmfb | ✅ 同 |
| 音频 | ❌ defer | ❌ `sound: MultiMedia1: error getting cpu dai name`（ADSP APR 链） | ❌ 同 |
| dmesg 形态 | 无限刷屏 | 45KB 稳态 | ~56KB 稳态 |

**触摸问题定论**：F12 描述符内容逐次开机不同（v13 全零 / v14a `02 00 00 00` / v14b 全部合法），「传感器需稳定时间」假设正确，但正确实现 = **快速失败（A-1）+ ≤3 次 defer（A-2）+ 放弃时清 IRQ 位**，赶上稳定窗口即成功——本轮 v14b 印证。

## 新暴露问题（v15 输入）

1. **`pclk0_clk_src: rcg didn't update` ×2**（v14b 2.33s）：mdp_clk_src 修复后暴露的下一环——DSI 像素时钟 RCG 换父时 DSI PHY PLL 未上电，与 P1 同族（父为 PHY PLL，需先弄清 DSI PLL enable 链，不宜照抄 B-2）。
2. **音频 cpu dai name**：`MultiMedia1: error getting cpu dai name` = q6asm/q6afe（ADSP APR）未起；G-C 已证两音频驱动 of_match 不冲突。
3. **ath10k `vdd-3.3-ch1 not found, using dummy`**：DTB 只有 ch0 无 ch1（WCN3990 需两路 ch 供电）。
4. **`reboot bootloader` 不通**：主线内核无重启原因→ABL 链路，进 fastboot 必须按住音量下。

## 产物与证据

- 归档：`backups/products/products_r11s_v14ab_20260902_0306/`（两镜像 + Image ×2 + ramdisk ×2 + SHA256SUMS + README + 两份全量 dmesg）
- 证据日志（入库）：`recon/v14a_dmesg_full_20260902.log`（618 行完整）、`recon/v14b_dmesg_full_20260902.log`（803 行，尾部 ~200B 串口捕获损坏，关键行均已抽取）
- 固件侧已落盘：`firmware/ath10k/WCN3990/hw1.0/firmware-5.bin`（A-5，版本未取证）、`firmware/qcom/a530_{pm4,pfp}.fw`（B-5，取自主机 linux-firmware 解压）
- 回滚链：v14b→v14a→v13→v12→v11→**v10**→v9→…→boot-debug.img（`4ff811c3…`）
- **设备当前状态：运行 v14b 救援 shell**（USB `18d1:d004`，ttyACM0 可交互）；p69 未格式化（23.2GB 在位）

---

# 2026-09-02（第三更）：v15 镜像已合成（待明早刷写实测，未触碰设备）

## 本轮做了什么（联网 + 实机证据驱动）

| 项 | 结论/落点 | commit |
|---|---|---|
| **V1 pclk0_clk_src** | 根因闭环：pclk 用 `clk_pixel_ops`、父为 DSI PHY PLL，而 DSI 路径**结构性先 set_rate 后 enable**（PLL 未起振 → CMD_UPDATE 不自清）。修复 = `pclk0/pclk1` 加 `CLK_OPS_PARENT_ENABLE`（与 mdp 同构） | `0d91b415a` |
| **C-4 双面板自动检测** | 推翻"probe 里读 ID"设想（probe 期 DCS 传输被 `dsi_host.c:1742` 拒绝）；改用**原厂已有机制**：ABL 在 cmdline 传 `mdss_mdp.panel=...sofeg01...` → 面板驱动按名字门控 attach（避免 VC 被覆盖）+ `dsi_bind` 按同名匹配选桥；无 cmdline 回落原 ep0 行为 | `4d8a852df` |
| **V4 WiFi ch1 供电** | `ath10k/snoc.c:48-52` 请求 5 路电源，DTB 只有 4 路 → 补 `vdd-3.3-ch1-supply`（与 ch0 同轨） | DTB 手术 |
| **音频可测化** | v14b 实机证明 adsp 只是**文件缺失（-2）非 crash** → adsp（13M）入 ramdisk；另发现真缺陷：`cdsp.mdt` 请求无前缀而清单在 `qcom/sdm660/` 下，rootfs 后也会失败 → 补根目录副本 | 打包侧 |
| **固件补齐** | ramdisk 增 BT / a530 / adsp / cdsp / ath10k；**modem 56MB 超 boot 预算，不装**（WiFi 的 modem-DSP 依赖留 rootfs 阶段） | 打包侧 |
| **a512_zap（V2）** | 联网未找到合法来源、本地 OTA 包内无该文件 → **未做**；GPU 3D 仍停在 zap，不做凭空改 DTB 的试探 | — |

## 产物

- 镜像：`out/v15/boot_r11s_v15.img` = `f944aaf7a6d076927aa1179d4a3305f56b5d738364f6f50c437bacaaa57f920a`（37,220,352 B）
- 归档：`backups/products/products_r11s_v15_20260902_1244/`（镜像 + Image_v15 + dtb_v15.dtb + ramdisk_v15.cpio + 手术 dts + SHA256SUMS + README）
- DTB 手术源：`backups/source/dtb_v15_surgery_20260902_1218/`（panel@1 启用+port、dsi0 port@1 双端点 ep0/ep1、ch1 供电；dtc 0 error，回读校验通过）
- 门禁：G1–G6 全通过（详见归档 README）

## 明早

- 测试清单：`recon/R11S_V15_MORNING_TEST_20260902.md`（A 显示时钟 / B 双面板门控 / C 触摸 / D 音频 / E GPU·WiFi / F 稳定性，每项含预期 dmesg 关键字与判定口径）。
- **刷写需你当次授权**（`fastboot flash boot out/v15/boot_r11s_v15.img`）；本轮未触碰设备，设备仍运行 v14b。
- 已知不要误判为失败：GPU 3D（缺 zap 合法来源）、WiFi（缺 modem 固件）、ramdisk 变大导致开机变慢。

# 2026-09-03 凌晨：接力恢复，锚点 v15b 重刷并验证
- 承接 9/2 v16a 上板中断（卡 logo + 263s 异常刷写 + USB -71，详见 out/test_flash_progress.md 9/3 节补账）
- v15b（cfa3a8ef…）在新 USB 口 1.65s 健康重刷；受控重启循环验证：uptime 全新、cmdline 无 r11root（=v15b）、救援 shell 正常。设备回到已知良好锚点
- 教训入库：fastboot 传输 D 状态卡死 = USB 链路病，30s 健康门掐断换口，绝不带病写入；hub 口 2-1.3 列为 -71 惯犯
- 下一步：v16a 上板（唯一变量=ramdisk r11root= init）→ p69 rootfs 部署（单独授权）→ SSH/ECM 验收
