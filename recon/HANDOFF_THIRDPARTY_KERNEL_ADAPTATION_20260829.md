# R11s 第三方内核驱动适配 — 接力交接书（2026-08-29）

> 用途：供接力 agent 无损续做。权威计划文件（勿编辑）：
> /home/<user>/.config/QoderCN/SharedClientCache/cache/plans/R11s_第三方内核驱动适配_54661c84.md

## 0. 一句话现状

以第三方镜像 /home/<user>/claude/r11/boot-r11s-btrfs.img（7.0.9-sdm660，R11T 版，能开机缺驱动）为新基线做驱动适配。阶段 0/1 已完成，阶段 2 重编进行到一半被中断（config 已固化、DTB 已编、Image.gz 未编出），刷写门禁未开始。设备关机、可进 fastboot。

## 1. 已完成（产物均在盘，可核验）

### 任务 1：镜像取证（完成）
- 镜像 = R11T 版 DTB（board-id 0x3EB3；R11s 需 0x4273）、无 watchdog 节点、内核 7.0.9、CONFIG_QCOM_WDT=m。
- rootfs 契约：ramdisk /init 按 PARTNAME 找 userdata 挂 btrfs subvol=@，失败进 USB ACM 救援 shell（0x18d1:0xd004 → ttyGS0）。cmdline 原值：`console=tty0 console=ttyGS0,115200n8 loglevel=7 rootwait rw`（ttyGS0 是救援 shell 配套，勿当误配）。
- 完整 .config 已从内核 IKCONFIG 提取（8100 行）。
- 解包产物：/tmp/r11s_btrfs_recon/（kernel.raw、appended.dts、ramdisk.cpio、rd/init、thirdparty_config.txt）。**/tmp 有清理风险，权威副本已归档（见任务 3）**。

### 任务 3：阶段 0 工程基线（完成）
- 归档（均含内容+SHA256SUMS+README）：
  - backups/products/products_r11s_thirdparty_baseline_20260827_0128/（boot-r11s-btrfs.img 副本，sha256 502274b5…469b558e）。**注意：该目录 README.md 已被用户手动清空（2026-08-29），后续编辑不要自行恢复内容**。
  - backups/products/products_r11s_thirdparty_recon_20260827_0128/（40M，9 文件：appended.dts、thirdparty_config.txt、ramdisk.cpio、rd/init、kernel.raw 等）
  - backups/products/products_r11s_upstream_reference_20260827_0155/（上游仓库根 r11s.dts 17377 行 sha256 984e2e0f…；r11s_pmos-firmware.zip 396499B sha256 4af2ef45…）
  - backups/source/fork_tree_keyfiles_20260827_0129/、backups/source/fork_tree_pre_gitinit_20260827_0129.tar.gz（1.4G）
- 适配树 git 基线：out/linux-sdm660-oppor11-t-qcom-sdm660-7.0.y，main 分支，提交 01fdb21b0541684a01b064dd5bf4ff9955412c14（93100 文件；已把 /build/ 加入 .gitignore）。提交身份用 `-c user.name=r11s-workspace -c user.email=r11s@local`，全局 git config 未动。
- 上游参考仓库：out/ref_upstream_linux-sdm660-oppor11_s（treeless 部分克隆 --depth 1 --filter=blob:none；全量克隆因 curl 56 TLS 断流 4 次失败，需要其他文件用 `git cat-file blob HEAD:<file>` 按需取）。只读参考，不参与构建。

### 任务 4：阶段 1 DTB 手术快验镜像（完成，未刷写）
- 产物：/home/<user>/claude/r11/out/boot_r11s_dtbsurg.img（11968512 B，sha256 94b07f708fd540219ca44891627fd978f9be0348c402559c41d03c79090293e7）
- 改动 = 恰好 4 处（model→OPPO R11s、compatible→oppo,r11s、board-id→0x4273、soc@0 内插 watchdog@17817000 kpss-wdt 节点），三重自检通过，头部全字段复刻原镜像（含 os_version 0x12000139 与原 cmdline），唯一差异 = kernel 段内新 DTB（+116B）。
- 实测更正：内核字段布局 = gzip 段（止于偏移 11234819）+ 64210B DTB，**没有 131B 空壳**（早前取证误记）。
- 归档：backups/products/products_r11s_dtbsurg_20260827_013308/（镜像+DTB+dts+kernel_field.bin+SHA256SUMS+README）。
- 已知局限：该镜像内核 QCOM_WDT=m 且 ramdisk 无模块，watchdog 节点不会自动喂狗；预期需救援 shell 内 `busybox devmem 0x1781700C 32 1` 手动喂狗（间隔 <60s）。

### 任务 5：阶段 2 本地树重编（部分完成，被进程重启中断）
已完成部分：
- 新构建目录 build/r11s_phase2/，.config = thirdparty_config.txt 种子 + `scripts/config --set-val QCOM_WDT y` + olddefconfig，已核验 QCOM_WDT=y。
- arch/arm64/configs/r11s_defconfig 已固化并提交：f4e9af176。
- DTB 已编出：build/r11s_phase2/arch/arm64/boot/dts/qcom/sdm660-oppo-r11s.dtb。

## 2. 未完成（接力从这里开始）

### 任务 5 剩余（最优先）
1. 继续构建（构建可增量续跑）：
   ```
   cd /home/<user>/claude/r11/out/linux-sdm660-oppor11-t-qcom-sdm660-7.0.y
   make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=build/r11s_phase2 -j$(nproc) Image.gz modules
   ```
   绝不在命令行传 LOCALVERSION=。模块若有编译失败：记录清单、不要改驱动源码救模块，先保 Image.gz。
2. 体积守门：`zcat build/r11s_phase2/arch/arm64/boot/Image.gz | wc -c` ≤ 0x3000000（31457280），超限停止汇报。
3. 打包（先读 tools/r11s_bootimg_pack.py 源码核参数名，默认先 dry-run）：
   ```
   python3 /home/<user>/claude/r11/tools/r11s_bootimg_pack.py \
     --kernel build/r11s_phase2/arch/arm64/boot/Image.gz（或 Image，以脚本支持为准） \
     --dtb build/r11s_phase2/arch/arm64/boot/dts/qcom/sdm660-oppo-r11s.dtb \
     --ramdisk backups/products/products_r11s_thirdparty_recon_20260827_0128/ramdisk.cpio \
     --base 0x80000000 --ramdisk-offset 0x3000000 --os-version 0x12000139 \
     --cmdline "console=tty0 console=ttyGS0,115200n8 loglevel=7 rootwait rw" \
     --out /home/<user>/claude/r11/out/boot_r11s_phase2.img
   ```
   ramdisk 原样使用绝不重压。dry-run 对账（总大小 <64MiB、解压后 image_size <0x3180000）通过后 --write。
4. 归档 backups/products/products_r11s_phase2_<ts>/：boot.img、Image.gz、dtb、.config、模块清单、SHA256SUMS、README（含回滚命令与验收标准）。
5. 若构建过程改了树内文件，补一个说明性 git commit。

### 任务 6：刷写门禁（两个镜像齐备后，必须逐次获用户当次确认）
- 阶段 1 镜像先刷（单变量验证第三方内核本体）：判定 = 15–25s 内 lsusb 出现 0x18d1:0xd004、ttyGS0 出 shell；WDT 预案 = 救援 shell 内手动喂狗（见任务 4 局限）。
- 阶段 2 镜像：验收 = 活过 60s 不落 900e、kpss-wdt probe、eMMC 枚举（PARTNAME=userdata 可读）、ttyGS0 救援可进。这是全部外设适配的总闸门。
- 回滚命令：`fastboot flash boot /home/<user>/claude/r11/boot-debug.img`（4.19 基线，sha256 4ff811c3…，已实测可启动回 Lineage）。
- `fastboot boot` 不被 R11s ABL 支持，只有 `flash boot` 一条路。
- 历史纪律：10+ 组盲刷全灭教训；用户 8/12 起"停止刷写、有把握再刷"，每次刷前展示命令+目标分区+回滚路径并获当次确认。

### 阶段 3：驱动适配迭代（任务 6 通过后）
- 模块策略：外设一律 =m（触摸 rmi4 <1MB 可破例 =y）；vermagic 变 7.0.14，第三方旧 .ko.zst 全失配，必须本地树自编模块，部署经救援 gadget（f_mass_storage 或 ECM/NCM+scp）入 /lib/modules/7.0.14-sdm660-gcc+/。
- 顺序：触摸（sdm660-oppo-r11t.dts:413 rmi4 节点模板，对照 /home/<user>/claude/r11/r11s..dts:11952）→ 显示（**先取证 R11s 面板型号**，第三方镜像的 s6e3fa3 是 R11T 面板，模板在树内 drivers/gpu/drm/panel/panel-samsung-s6e3fa3.c）→ 音频（sdm660-oppo-r11t.dts 176–283 行 &sound，驱动树内 sound/soc/qcom/sdm660-internal.c）→ WiFi/BT（原厂 r11s..dts:4285 + r11s_pmos-firmware.zip 固件）→ 电池/充电（bq27541 → BATTERY_BQ27XXX；qpnp-smb2 对 PM660 支持单列调研）。
- 每步循环：改 config/DTS → 提交 → 构建（体积守门）→ 打包（dry-run 对账）→ 用户确认 → 刷写 → 判定 → 结论写 out/test_flash_progress.md + recon/ → 归档。

### 阶段 4：rootfs（userdata btrfs subvol=@）
- 单独立项、单独授权；动手前 `btrfs check --readonly` + 只读挂载。阶段 1–3 全程靠救援 shell，无需部署。

## 3. 硬约束速查
- ABL 门限：解压后 image_size < 0x3180000；boot 分区 64MiB；board-id 必须 0x4273（R11T 是 0x3EB3，勿混）。
- R11s bootloader 武装 60s 启动窗口 WDT（APSS @0x17817000），DTB 必须含可绑定的 watchdog 节点且驱动内建，否则 60s 咬死落 900e（05c6:900e）。
- 9008/900e 仅作原厂恢复（backups/factory/R11s_11_C.19_1190_20201031/），禁 EDL 自定义刷写。
- 纪律：改源先备份入 backups/source/；产物即归档 backups/products/ 带 SHA256SUMS+README；结论写 recon/（已证实/未证实分开）；不混用 MTK/R11/R11T 结论。
- 状态记录：out/test_flash_progress.md（实测日志）、/home/<user>/claude/r11/STATUS.md（需补 8/27 之后进展）、/home/<user>/claude/r11/CLAUDE.md（规则书，动手前先读）。

## 8. 增补：2026-08-29 夜间进度快照（本会话）
- 阶段 1/2 上板验证完成：v2（自编 7.0.14 + 手术 DTB）实测 PASS（活过 60s、watchdog0 绑定、eMMC 枚举、救援 shell）；树内极简 DTB 缺早期节点是历来 900e 元凶（定案）。
- 作者镜像（boot-r11s-NEW.img 及 +watchdog 手术版）在本机两连测均无限重启 → 降级为节点参数参考。
- 显示打通（v6，里程碑）：面板三星 SOFEG01_S 自研驱动（原厂参数移植）+ DRM_MSM=y + REGULATOR_QCOM_OLEDB=y，fbcon 上屏（用户确认可见企鹅+日志）。
- 触摸进展：probe 中止已修（重复 PDT 条目跳过）；供电设压已修（vio L14 1.8V，中断 0→88）；rmi_i2c 10×20ms 重试已加；残留 = F12 未绑定（报错 83µs 完成、无重试日志，定位在 rmi_read_register_desc 的 size_presence>35 校验）→ v8 修复任务保留未开工。
- git 上传：源码树 → github.com/lxjuyn/r11s-mainline-kernel（双语 README）；7 个阶段镜像按阶段发布为 Releases（stage1-dtbsurg … stage3-touch-v7）；products 仓库已删。今后每步产物直接挂 Releases（用户纪律：每步完成即提交推送，不攒批）。

## 9. 增补：2026-08-30 凌晨进度快照（接力后新一轮）
- **触摸定案**：v8 上板实证 I2C/传感器/中断全好（用户划屏产生真实中断），唯一故障 = F12 PDT 扫描布局；Nick 对照原厂修复：PDT_END 0x05→0xd0、10 页扫描上限、幽灵函数白名单、原厂布局回退。
- **四路集成镜像 v9**：out/boot_r11s_phase3_integrated_v9.img（15,081,472 B，sha256 c34f1307…）= 触摸 PDT 修复 + 音频链源码（AK4376/MAX98927L/glue 机器驱动，声卡因 DTB 下游绑定预期不注册）+ WiFi/蓝牙 config（WCN3990，零源码改动）+ 电池/充电（qcom_smbx 限流钳位 1.5A，DTB battery@4000 节点已打开）；树内提交 d947f542d 已推，Release `stage3-integrated-v9` 已发。
- **原厂面板逆向**（用户指定方法）：原厂 boot 内核段无面板 compatible（MDSS 为 DT 数据驱动），权威集合取 17011 编译链 = sofeg01_s（已支持）+ ams596w401（新移植 538 行驱动 + DTB 节点，优雅失败不回退显示链）。
- **固件盘点**（Sarah）：backups/firmware_inventory_r11s_20260830_043151/，部署集 110 文件 83MiB（含此前缺失的 adsp/cdsp mdt 段、venus、fastrpc 库）；定案固件走 rootfs /lib/firmware，不进 ramdisk（超 64MB boot 上限）。
- **rootfs 方案**：recon/PHASE4_ROOTFS_PLAN_20260830.md；目标分区 /dev/mmcblk1p69（userdata ~46.3GiB）；写入路径 = 救援 shell 拉 configfs mass_storage LUN + 主机 dd（脚本 tools/r11s_phase4_emmc_setup.sh，默认干跑）。
- **v10 切根镜像**（Jack）：out/boot_r11s_phase4_rootfs_v10.img（15,081,472 B，sha256 28773a5c…）= v9 kernel+DTB 逐字节复用 + 新 /init（支持 root=/dev/mmcblk1p69 挂载切根，任何失败落回救援 shell 防砖）；Release `stage4-rootfs-v10` 已发。
- **阶段 4a rootfs 成品**（Hunk）：out/r11s_phase4a_rootfs.ext4（160MiB，sha256 37db33b7…）= Alpine 3.24.1 minirootfs + 110 固件文件（sha256 全过）+ gadget 自拉起（18d1:d004/ttyGS0）+ getty 重生 + r11s-diag 巡检；归档 backups/products/products_r11s_phase4a_rootfs_20260830_045727/。
- **待办链（待用户授权）**：①刷 v9 验收四路（触摸应出坐标）；②刷 v10（p69 未格式化时行为同 v9）；③授权格式化 p69 + 写 rootfs（需用户当次确认，脚本双重确认）；④回滚链：v10→v9→v8→…→boot-debug.img。
- **设备当前状态**：停在 fastboot（18d1:d00d），boot 链完好。

## 10. 增补：2026-08-30 清晨进度快照（v11 音频候选 + rootfs v2 模块层，纯主机侧）
- **v11 音频候选镜像**：out/boot_r11s_phase3_audio_v11.img（15,101,952 B，sha256 a07a5ef5…）= 音频链 8 项转 =y（无模块依赖）+ 候选 DTB 两行修复 + glue 机器驱动禁用 + TFA9890 驱动树内已有；构建源 build/r11s_phase2（与 v9/v10 同源，vermagic 7.0.14-sdm660-gcc++）。候选件，未刷。
- **rootfs v2（补模块层）**：v1 无 /lib/modules，未来 =m 驱动会失效；本轮把 v11 构建全量模块层补入。模块集 681 个 .ko.zst（strip 后 12MiB），目录 /lib/modules/7.0.14-sdm660-gcc++，vermagic 与 v11 内核实测一致；depmod 主机侧打包时已完成（设备侧无需重跑）；无固件重复件。
- **新成品**：out/r11s_phase4a_rootfs_v2.ext4（192MiB，sha256 37515502…），ext4 特性与 v1 一致，余量 36%，e2fsck -fn 干净，只读挂载抽检通过；旧件 out/r11s_phase4a_rootfs.ext4（37db33b7…）原样保留作回滚件。
- **归档**：backups/products/products_r11s_phase4a_rootfs_v2_20260830_060453/（双语 README + SHA256SUMS + 树清单；镜像 >100MB 原位留 out/）。
- **待办链不变（待用户授权）**：刷 v11 → 刷 v10 → 授权格式化 p69 + 写 rootfs（用 v2 件）；设备仍停 fastboot（18d1:d00d），boot 链完好。

## 11. 增补：2026-08-30 清晨进度快照（rootfs v3 = v2 + WiFi userspace 四件套，纯主机侧，主机侧准备全部完成）
- **rootfs v3（任务 #36）**：在 v2（37515502…）基础上并入任务 #35 的 WCN3990 WiFi userspace 四件套（全静态 aarch64，qemu 冒烟已过）。全部为纯追加：四二进制入 /sbin/（0755 root:root）+ /sbin/init 追加启动段（pd-mapper 先、rmtfs -o /var/lib/rmtfs -v 后，均后台，日志落 /var/log/；原 ACM gadget/getty 契约逐字节未动）+ 预建 /var/lib/rmtfs 与 /var/log。隐私红线实测干净（二进制与树均无用户名/路径/凭据痕迹）。
- **新成品**：out/r11s_phase4a_rootfs_v3.ext4（192MiB，sha256 f54772b7de0b69c026cb8cb73e30ca66e95ea664a62734568b080073012d606b），余量 35%，e2fsck -fn 干净，只读挂载抽检通过（四件在位、/lib/modules 681 个 .ko.zst 与 /lib/firmware 110 文件原样）。归档 backups/products/products_r11s_phase4a_rootfs_v3_20260830_061807/。
- **主机侧准备全部完成**：v11 内核镜像 + v3 rootfs 配套就绪；待办链不变（刷 v11 → 刷 v10 → 授权格式化 p69 + 写 rootfs 用 v3 件），设备仍停 fastboot（18d1:d00d）。旧件（v2、v1、phase4a_v2_work 树）原样保留作回滚。
