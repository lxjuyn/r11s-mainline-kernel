# R11s 阶段 4：rootfs 方案定案（2026-08-30）

> 任务 28 产出。**纯主机侧规划**：本文 + `tools/r11s_phase4_emmc_setup.sh`（干跑）+
> `rootfs/phase4_skeleton_20260830/`（骨架镜像）+ `backups/firmware_inventory_r11s_20260830_043151/`（固件盘点）。
> 未触碰设备、未刷写、未改适配树源码。

## 0. 一句话定案

**固件（83.0 MiB 部署集）不进救援 ramdisk，全部走 eMMC rootfs 的 /lib/firmware；
rootfs 落在 /dev/mmcblk1p69（GPT PARTNAME=userdata，~46.3 GiB，mkfs.ext4），
v10 起 cmdline 加 `root=/dev/mmcblk1p69 rootwait rw`（PARTUUID 为备用写法），
救援镜像原样保留作回滚件。**

## 1. 已核实的板级事实（来源标注）

| 事实 | 值 | 来源 |
|---|---|---|
| eMMC 设备节点 | **/dev/mmcblk1**（非任务书/旧文档的 mmcblk0） | out/test_flash_progress.md 阶段 1/2 实测（61,071,360 KB） |
| 分区布局 | 经典单槽 69 分区；**userdata = p69 ≈ 46.3 GiB**；system=p66、vendor=p67、dsp=p34、modem=p64、boot=p21 | recon/R11s_17011_PARTITION_LAYOUT_20260809.md + dtbsurg 首刷 /proc/partitions 实证 |
| boot 分区 | 64 MiB；ABL 另限解压后 Image ≤ 50,331,648 B | HANDOFF_THIRDPARTY_KERNEL_ADAPTATION_20260829.md §3 |
| 现行 cmdline | `console=tty0 console=ttyGS0,115200n8 loglevel=7 rootwait rw`（**无 root=**） | 同上 + v9 打包参数 |
| 救援通道 | USB ACM gadget 18d1:d004 → ttyGS0 busybox shell；/init 找 PARTNAME=userdata 挂 btrfs subvol=@，失败落 shell（现网即走此兜底） | products_r11s_thirdparty_recon_20260827_0128/rd/init（已读源码） |
| 固件部署集 | 83.0 MiB / 110 文件（adsp/cdsp/venus + fastrpc 库 + modem + WCN3990 + qca BT） | backups/firmware_inventory_r11s_20260830_043151/（本任务提取盘点） |
| 主机既有资产 | ① `rootfs/ubuntu-arm64/`（Noble 24.04.3 树，235M，systemd/udev/iproute2/kmod 齐）② `backups/products/products_r11s_ubuntu_rootfs_20260809_222410/r11s-ubuntu-noble-arm64.ext4`（512MB 旧镜像，可参考结构）③ `rootfs/pmos-arm64/`（Alpine 3.24.1 minirootfs 已解，8.9M）④ `out/alpine-minirootfs-3.24.1-aarch64.tar.gz`（4MB 原始件）⑤ 主机有 `mke2fs`、`qemu-aarch64-static` | 本任务盘点 |

## 2. ramdisk vs rootfs 体积定案

| 项 | 数字 |
|---|---|
| 固件部署集 | **83.0 MiB**（87,045,739 B；gzip 后估计仍 >55 MiB，mdt 段压缩率低） |
| boot 分区上限 | 64 MiB（kernel+DTB+ramdisk+头 合计） |
| 现行救援 ramdisk | ~4 MiB |
| ABL 解压后 Image 上限 | 50,331,648 B |

结论：**ramdisk 路线物理不可行**（83 MiB > 64 MiB 分区，连"去掉 kernel 全塞固件"都不够）。
定案：**固件随 rootfs 上 eMMC**。救援 ramdisk 维持 ~4 MiB 最小形态，其职责 =
root 挂载失败兜底 + 回滚件 + 本阶段 eMMC 施工的操作通道。

## 3. rootfs 选型（两条路线，建议两段式）

### 路线 A：Alpine minirootfs（阶段 4a，验证环）
- 材料：`rootfs/pmos-arm64/`（已解 8.9M）+ 固件树 83 MiB + 少量配置。
- 制作（主机侧，**无需 qemu、无需 sudo**）：往树里放固件与 /etc 配置 →
  `mke2fs -d <stage目录> -t ext4 r11s-alpine-rootfs.ext4 256M`。
- 利：体积小（镜像 ~100 MB，USB 传输快）；与救援 busybox 心智一致；最快打通
  "root= 挂载 → switch_root → getty → 固件可见"这条主链。
- 弊：musl + 无 systemd/udev；WiFi 所需的 rmtfs/pd-mapper/tqftpserv（QMI userspace）
  需自源码交叉编译（musl 可编但费时）；包生态靠 apk。
- **定位：只用来说明"阶段 4 本体通了"，不作为最终 userspace。**

### 路线 B：Ubuntu Noble arm64（阶段 4b，正式 userspace）
- 材料：`rootfs/ubuntu-arm64/`（8/9 已构建核验过的 Noble 24.04.3 树，235M，
  systemd/udev/iproute2/kmod/dhcp 齐，纯 arm64 无污染——见 STATUS 8/1 记录）。
- 制作：树内叠加 /lib/firmware（83 MiB）+ /etc 配置（getty、rmtfs 服务）→
  `mke2fs -d` 出 512 MiB ext4 镜像（与既有 512MB 旧镜像同规格；旧镜像可作结构参考）。
- 利：systemd/udev 天然管 remoteproc sysfs 重绑、getty、QMI 服务；glibc 生态可直接
  编/装 rmtfs 全家桶（pmOS SDM845 同款依赖）；阶段 5 音频/WiFi 迭代效率高。
- 弊：体积大（512 MiB 镜像，USB2 传 ~1–2 min，可接受）；debootstrap 环节已被 8/9
  的工作替代（**无需重新 debootstrap**，直接复用现有树）。
- 备选：如担心 8/9 树陈旧，可用 `qemu-aarch64-static + debootstrap --foreign` 重做
  （主机已具备），成本 ~30 min，非必需。

**定案：先 4a（Alpine 最小环，一天内可闭环验证 root= 与固件可见性），
通过后 4b（Ubuntu Noble 正式环）。两者共用同一分区与同一写入脚本。**

## 4. 分区与写入路径（设备 /dev/mmcblk1）

### 4.1 分区选择
- **用 p69（userdata）**：OTA/主链不依赖它（mainline 链无 Android 系统概念），
  46.3 GiB 充裕，分区布局取证报告 §建议1 亦指明此处。
- **不动分区表**：不 parted 新建/改分区（Android GPT 69 分区 + 尾部备份 GPT，
  动表风险远大于收益）；p69 原样格式化。**格式化会清掉 p69 内原有数据**——
  施工前须用户当次确认（脚本内置二次确认，干跑默认只打印）。
- 备选（若日后不想牺牲 userdata 原厂数据）：在主机把 p69 整区 ddread 备份
  （46 GiB，USB2 下 ~40 min，救援 shell 走 mass storage LUN 可做）；本期不做，仅留口。

### 4.2 主机 → 设备传输路径（救援 shell 已验证的 gadget 能力范围内）
首选：**configfs f_mass_storage**（救援 busybox 具备 configfs + gadget 操作先例——
/init 即用 configfs 拉 ACM）。设备侧把 `/dev/mmcblk1p69` 挂为 LUN 暴露给主机，
主机侧直接 `mkfs.ext4 /dev/sdX`（格式化在主机做，省去设备侧缺 mkfs.ext4 的问题）
+ `dd if=镜像 of=/dev/sdX bs=4M conv=fsync` + `e2fsck -fn` 校验。
- 备选 1：设备侧 base64 收静态 mkfs.ext4（同法曾推过 rmi4dump_raw），设备自己格式化。
- 备选 2：ECM/NCM gadget + busybox nc 流式写入（无 mass storage 时的退路）。
- **禁用**：任何经主机 adb/fastboot 写 userdata 的路径（fastboot 对 userdata 的
  格式语义不可控，且违反"救援通道内施工、可逐步验证"的纪律）。

### 4.3 施工序列（对应 `tools/r11s_phase4_emmc_setup.sh`，设备侧脚本，本轮不执行）
1. 预检：`/dev/mmcblk1` 存在、p69 PARTNAME=userdata、p69 未被挂载、容量 ≥ 镜像。
2. 拉 mass storage gadget（LUN file=/dev/mmcblk1p69）→ 主机完成格式化+dd+校验 → 设备侧卸载。
3. 设备侧只读挂载抽查（/sbin/init 存在、/lib/firmware/adsp.mdt 存在、sha256 抽检）。
4. 记录：`cat /proc/partitions`、`dmesg | tail` 落盘串口日志作为施工证据。

## 5. 内核侧配合与固件加载时序

### 5.1 cmdline（v10 起）
```
console=tty0 console=ttyGS0,115200n8 loglevel=7 rootwait rw root=/dev/mmcblk1p69
```
- 主写 `/dev/mmcblk1p69`（本机已实证节点名）；备用写 `root=PARTUUID=<p69的GPT UUID>`
  （施工时救援 shell 里 `blkid -s PARTUUID` 或读 /sys 取得后固化）。
- `rootwait` 保留：eMMC 枚举晚于 cmdline 解析时必须等。
- 现行 `rdinit=/init` 语义不变（救援 ramdisk 仍全程在场，由它 switch_root）。

### 5.2 /init 改造（v10 重打 ramdisk 时；本轮不改任何文件，仅定规格）
现行 /init 硬编码 "btrfs + subvol=@"。v10 需改为：
1. 解析 /proc/cmdline 的 `root=`（缺省回退 PARTNAME=userdata 扫描，与现状兼容）；
2. 按文件系统在 `ext4`（新）与 `btrfs subvol=@`（旧契约）间自适应试挂；
3. 挂载失败仍落现有 emergency ACM shell（回滚行为不变）；
4. 成功则照旧 move mounts + `switch_root /newroot /sbin/init`。

### 5.3 固件加载时序（重点）
- 内核固件搜索路径 = rootfs `/lib/firmware`（mainline 默认；可用
  `firmware_class.path=` 覆盖，本方案无需覆盖）。
- **时序风险**：remoteproc 系驱动全部 =y（config 现状），probe 可能发生在
  root 挂载前；此时 `request_firmware()` 直接读文件系统 → -ENOENT →
  probe 失败，且多数 remoteproc 驱动**不会自动重试**。
- **缓解（写入 rootfs init 规格）**：rootfs 起来后（systemd unit 或 rc 脚本）对
  `qcom_q6v5_adsp / qcom_q6v5_mss / qcom_q6v5_pas` 驱动做
  `echo > /sys/bus/platform/drivers/<drv>/unbind` + `bind` 重触发 probe；
  此时 /lib/firmware 已就位，mdt_loader 正常加载。若 probe 本就发生在挂载后
  （依赖时钟/电源链常会 defer 到很晚），重绑也无害（幂等）。
- WiFi 额外依赖（任务 25 结论，不重复）：modem(MPSS) 先起 + rmtfs/pd-mapper/
  tqftpserv userspace 服务 → 归阶段 5，但 **r11s 用户态必须预装这些服务**
  （4b Ubuntu 树制作时打包进镜像）。
- 救援态（无 root=）：固件请求全失败为**预期行为**，不阻塞救援功能（v9 已验证无害）。

### 5.4 与救援镜像的关系
- 救援镜像（v9 ramdisk/boot.img）**原样保留**：每次阶段 4/5 上板前先确认能回
  救援态（回滚件 = v8/v9 镜像 + `fastboot flash boot` 已验证路径）。
- root= 生效的前提是 p69 已有有效 ext4；p69 被清空/损坏时，/init 挂载失败自动
  落回救援 shell——即"rootfs 坏了也变不砖"，这是本设计的结构性保险。

## 6. init 规格（rootfs 侧最小职责）

4a（Alpine，busybox-init/OpenRC）：
1. 挂 /proc /sys /dev（devtmpfs）、启动 mdev/udev 等价；
2. `getty` 挂到 `ttyGS0`（ACM gadget 由 rootfs 侧重新拉——救援 /init 切换前
   已占用该 gadget 的话，v10 /init 需在 switch_root 前关闭救援 gadget，
   **规格：/init 进 rootfs 路径时先 `echo > $g/UDC` 解绑再切换**，避免双主）；
3. 执行 §5.3 的 remoteproc unbind/bind 重触发；
4. 固件就位确认脚本：`ls /lib/firmware/qcom/sdm660/adsp.mdt` 等 3 文件点检。

4b（Ubuntu，systemd）：getty@ttyGS0 由 udev/systemd 自动；新增
`r11s-remoteproc-rebind.service`（oneshot，After=local-fs.target）做 §5.3 重绑。

## 7. 本轮已落盘产物

| 产物 | 位置 | 说明 |
|---|---|---|
| 固件盘点（136 文件 + NOTE + INVENTORY.tsv + SHA256SUMS） | backups/firmware_inventory_r11s_20260830_043151/ | 部署集 83.0 MiB 按 /lib/firmware 布局 |
| 最小骨架 ext4（100 MiB，目录树 + 全套部署固件） | rootfs/phase4_skeleton_20260830/r11s-rootfs-skeleton.ext4 | e2fsck 通过；**不是可启动 rootfs**（无 userspace），仅验证布局/体积/打包管道 |
| 施工脚本（干跑默认） | tools/r11s_phase4_emmc_setup.sh | 救援 shell 内运行，本轮不执行 |
| 本方案 | recon/PHASE4_ROOTFS_PLAN_20260830.md | — |

## 8. 遗留风险清单

1. **p69 格式化不可逆**（脚本有 --really + 二次确认，仍须用户当次授权）。
2. mass storage gadget 在救援 busybox 下的可用性**未实机验证**（configfs 拉
   ACM 已验证；f_mass_storage 同框架，风险低但非零）——首次施工先在救援态试拉。
3. /init 改造是 v10 的打包工作，本文只定规格；未改任何现行文件。
4. remoteproc 早于 root 挂载 probe 的实际发生率未实证（靠重绑兜底，阶段 5 上板看
   dmesg 确认）。
5. Ubuntu 树（8/9）距今已 3 周，内核侧已演进到 7.0.14 自编链；4b 制作时需复核
   树内 /etc 与内核版本匹配（vermagic、modules 目录）。
6. WiFi board-data 仍依赖运行时 qmi_board_id 精修（任务 25 风险 3，不变）。
7. BT MAC / WiFi MAC 来源未定（原厂 nvram 提取属阶段 5）。
