# Oppo R11s（SDM660）主线 Linux + Ubuntu：移植方向指南（审阅版）

> **状态：仅调研与规划。**本文不包含且尚未执行解锁、刷写、EDL、写入分区、下载源码、生成 rootfs 等操作。
>
> 当前只创建了空目录：`/home/<user>/claude/r11/{recon,build,tools,out,backups}`。请先审阅此路线，再决定是否做设备取证与上板验证。

---

## 1. 结论先行

可以尝试，但不是将 MT6572 的编译命令替换一下便能得到 Ubuntu 的任务。

Oppo R11s 是 **Qualcomm Snapdragon 660（SDM660，64 位 ARM）**，并非 MediaTek。Linux 主线已有 SDM660 的 SoC 支持，并有同 SoC 消费设备的参考 DTS；但调研未找到可直接使用的 **Oppo R11s 专用 mainline DTS、postmarketOS 设备包、Halium/UBports 移植或现成主线分支**。

项目本质是：以主线 SDM660 SoC 支持为基础，重建 R11s 的板级设备树与启动镜像兼容性，最后由主线内核启动 Ubuntu arm64 用户态。

第一阶段的成功标准不应是“可日用的 Ubuntu 手机”，而是：安全地临时引导内核、获得稳定早期日志、识别存储、启动一个 Ubuntu shell。显示、触摸、音频、modem、Wi-Fi/蓝牙、相机、充电与低功耗都属于后续独立工作包。

---

## 2. R11s 与 MT6572 项目的根本差异

| 维度 | 佳伯 Z1 / MT6572 | Oppo R11s / SDM660 | 直接影响 |
|---|---|---|---|
| CPU 架构 | 32 位 ARMv7 | 64 位 ARMv8-A | 使用 `ARCH=arm64` 与 aarch64 工具链 |
| SoC | MediaTek | Qualcomm | 不复用 MTK DTS、WDT、Wi-Fi、PMIC 或驱动结论 |
| 上游基础 | MT6572 多需 fork/自补 | SDM660 已有 `sdm660.dtsi` | 工作重点是 R11s board DTS |
| 引导 | Preloader/LK/ATAG 类旧链 | Qualcomm XBL/SBL/ABL 或 aboot，随固件不同 | 不套用 appended-DTB / ATAG-DTB 修法 |
| 刷写 | mtkclient | fastboot；深救援才可能 EDL | 先确认 bootloader 状态和分区，再谈刷写 |
| 调试 | C3 UART 已就绪 | TTL 很难引出，优先使用手机 USB 口作为 gadget 串口/USB 网络 | 首先使 R11s 以 USB device 身份枚举；外接 USB 转 TTL 不能替代 UART |

**最重要的边界：**6572 的项目管理与排错方法可复用；MTK 的板级技术结论不可照搬。尤其不能把 `mkbootimg --mtk`、MTK header、ATAG、WDT 寄存器、Preloader LineState、MT6620、MT6323 当作 R11s 的事实。

---

## 3. 当前已知资料与可信程度

### 3.1 外部硬件资料（须由真机复核）

- R11s 通常称为 CPH1717，常见别名有 OP56A7 / OP56AB / OP56BA；先确认手上实际机型、地区和 ColorOS 固件版本。
- SoC 为 Qualcomm Snapdragon 660 / SDM660，Kryo 260 八核；R11s Plus 不应混同，它是不同的 Snapdragon 835 平台。
- 常见规格为 4/6 GB LPDDR4X、64/128 GB eMMC 5.1、AMOLED、Android 7.1.1/ColorOS 3.2 年代固件。
- 公开资料并不足以给出面板型号、触摸 IC、PMIC 型号、eMMC 分区、实际 boot image header、bootloader lock 状态和 UART 引脚。这些都必须由原厂镜像、下游 DTS/内核源或真机只读取证确认。

### 3.2 上游 SDM660 支持

主线树存在：

- `arch/arm64/boot/dts/qcom/sdm660.dtsi`
- 其共同基础：`sdm630.dtsi`
- 已有同 SoC 的参考板：`sdm660-xiaomi-lavender.dts`（Redmi Note 7）

可作为第一阶段依据的上游组件包括：GICv3、GCC 时钟、TLMM pinctrl、SPMI、QFPROM、热传感器、eMMC/SD（SDHCI-MSM）、DWC3 USB、BLSP UART、部分 MDP5/DSI、IOMMU，以及部分 DSP/IPC 节点。

仍应视为高风险或后置的部分：

- R11s 面板及显示电源时序；SDM660 是 MDP5 时代平台，显示路径并不等于现代 DPU 平台；
- Adreno A512 的高性能 OPP/供电；
- 音频 ASoC 与 PMIC codec；
- WCN3990 Wi-Fi/蓝牙固件与供电/天线控制；
- modem、ADSP、CDSP remoteproc（需专有固件、保留内存与安全调用）；
- 相机、指纹、VOOC 快充、休眠/深度省电。

---

## 4. 建议的阶段路线

### 阶段 0：安全门禁与只读取证（尚未开始）

目标：先知道“能否安全测试、原厂状态如何、出了问题怎样回滚”，不改动设备。

应收集：

1. 真实型号、ColorOS build fingerprint、Android 版本、bootloader 是否可解锁；
2. `fastboot getvar all` 的文本输出（若设备可进 fastboot）；
3. 原厂 `boot`、`recovery`、`dtbo`（若存在）、分区表及对应 hash 的**只读备份**；
4. 原厂 boot image 解包结果：header 版本、page size、kernel/ramdisk/dtb/dtbo 位置、cmdline、AVB 关系；
5. 可取得的 Oppo kernel source、Android 下游 DTS、固件包、分区 XML / firehose 信息（仅用于研究）；
6. 调试通道：以**手机 USB 口 gadget**为主（CDC ACM 串口、ECM/NCM USB 网络），并保留 pstore/ramoops；硬件 UART test pad 仅作为并行、后置取证项。

**退出条件：**原厂可恢复镜像已经完整备份并校验；确认存在明确的、不依赖猜测的恢复路径。否则不进入任何写入或 unlock 操作。

### 阶段 1：建立可复现的主线构建，不上设备

目标：只在主机完成“上游内核能编、参考 DTS 能编、生成物可检查”。

建议目录：

```text
/home/<user>/claude/r11/
├── CLAUDE.md                 # R11 项目规则（尚待审阅后写入）
├── R11S_MAINLINE_UBUNTU_GUIDE.md
├── recon/                    # 只读资料、设备取证报告、来源链接
├── linux/                    # 独立的上游 Linux checkout（以后才 clone）
├── build/                    # out-of-tree 内核构建目录
├── rootfs/                   # Ubuntu arm64 rootfs（以后才创建）
├── tools/                    # 经审阅的解包、验证、日志脚本
├── out/                      # 临时构建结果；不可当唯一备份
└── backups/
    ├── source/               # 改动前源码备份
    ├── factory/              # 原厂只读镜像与校验
    └── products/             # 每轮可引导产物的时间戳归档
```

建议选用稳定、近期的 upstream Linux release，而非先 fork 一个 R11 专用树。编译基线示例（**仅供未来参考，本阶段不执行**）：

```bash
make -C linux O=../build ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
make -C linux O=../build ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom/sdm660-xiaomi-lavender.dtb Image.gz modules
```

注意：参考板 DTS 的成功只证明工具链与 SDM660 公共 DTS 没有问题，**不能**直接作为 R11s 镜像上板。

### 阶段 2：R11s 设备树取证与最小 board DTS

目标：以 R11s 下游信息为证据，不靠猜测写最小 DTS。

建议的最小 bring-up DTS 只包含：

1. `sdm660.dtsi` 公共基础；
2. chosen / bootargs；
3. RAM reserved-memory（严格匹配下游）；
4. 核心 regulator 与 PMIC 节点；
5. eMMC（rootfs 需要）；
6. 一个已验证的 debug 输出通道；
7. reset、pinctrl、必要时 USB device 模式。

不要在最初 DTS 中加入面板、触摸、音频、Wi-Fi、modem、摄像头。每增加一个外设就增加时钟、regulator、GPIO、interconnect 或固件导致早期死机的机会。

证据优先级应为：R11s 原厂 DTS/内核源 > R11s boot DTB/DTBO > R11s 拆机硬件证据 > 同 SoC 同 PMIC 设备 > Redmi Note 7 参考 DTS > 纯推测。低优先级来源不得直接成为可刷镜像的硬件参数。

### 阶段 3：不破坏式启动策略与早期日志

目标：先选择风险最低的启动路径。

当前设备状态（用户已确认）：**R11s 可解锁，且能够进入 Qualcomm 9008（EDL）模式；但 9008 不可用于刷写自定义固件。**因此本项目把 9008 仅定位为原厂恢复/救援通道，不把它当作 mainline 内核测试或自定义镜像写入途径。主开发路径应优先验证已解锁 bootloader 下的 fastboot 能力，特别是是否实际支持非破坏式 `fastboot boot`；在未实测前，不能假定它可用。

优先次序建议：

1. 已解锁且 `fastboot boot` 被**实际证实**可用：只临时装载，断电可回原厂；这是首选 mainline 测试路径；
2. 若 `fastboot boot` 不可用但 fastboot 允许写入：只有在完整原厂备份、明确分区名、验证镜像格式与恢复方法后，才评估受控的 boot 分区测试；
3. 若只能通过 recovery 启动：使用可验证、可回滚的临时 boot 路径；
4. 9008/EDL 仅作为原厂恢复和深度救援机制；已知其不能刷写自定义固件时，不尝试绕过该限制，也不将其作为开发流程的一环。

早期可观测性按本项目的实际可行性排序：**USB gadget（先 CDC ACM，后 ECM/NCM）** > pstore/ramoops 持久日志 > framebuffer > 硬件 UART（若日后可靠引出）> 盲猜。USB gadget 的前提是内核已经完成 DWC3、USB PHY、时钟/复位、供电、角色检测并注册 UDC；所以它**不能**定位解压、页表、GIC 等发生在 USB probe 之前的死机。为覆盖该盲区，应同时保留 ramoops/pstore 和可读的显示/bootloader 证据。

这里的“USB 转 TTL”必须严格区分两件事：

- 将普通 USB-to-TTL 转换器插入手机 USB-C/Micro-USB 口，**不会**变成手机的早期 UART console。该适配器本身也是 USB 外设；手机必须工作在 USB host、成功枚举并加载 usb-serial 驱动后，才可能在手机端产生 `/dev/ttyUSB*`，它不会把手机内核日志送回 PC。更不能把 TTL TX/RX 直接接到 USB D+/D−，这在电气和协议上都错误，可能损伤硬件。
- 可行的“USB 串口”是让**手机作为 USB device/gadget**：主线在 DWC3 UDC 注册后挂 CDC ACM function，PC 会出现 `/dev/ttyACM*`，手机侧通常为 `/dev/ttyGS0`。它适合作为 userspace shell、getty 和日志通道，而不是最早期的 printk console。随后加入 ECM/NCM USB 网络，PC 可经 SSH 同时获得 shell、文件传输和日志。

上游同 SoC 的 `sdm660-xiaomi-lavender.dts` 提供了结构性参考：`&usb3`、`&usb3_dwc3`、`&qusb2phy0`，并以 `dr_mode = "peripheral"`、PHY supplies、`extcon` 关联展示了 SDM660 的 DWC3 peripheral 接入方式；这些是**参考模板，不是 R11s 电气事实**。R11s 的 regulator、USB 角色检测、extcon/Type-C、PHY 与最大速率必须从 R11s 下游 DTS 或原厂 DTB 取证。

### 阶段 4：启动 Ubuntu arm64 shell

目标：看到 shell 即成功，不追桌面。

最小 rootfs 可选 Ubuntu Base arm64 + initramfs，或 Ubuntu Base 放 eMMC/外置 SD。优先 initramfs 原因：不依赖 eMMC 分区和 ext4 初期不确定性；缺点是镜像较大、维护不便。

建议最初 rootfs 只含：`/init`、busybox 或 systemd 最小环境、`mount`、`dmesg`、`ip`、用于导出日志的脚本。确认内核可稳定运行后，再换完整 Ubuntu Base，并通过 USB networking/SSH 或 console 登录。

### 阶段 5：外设按依赖顺序点亮

推荐顺序：

1. watchdog / reset 原因 / pstore；
2. **DWC3 peripheral UDC → CDC ACM gadget（PC 侧 `/dev/ttyACM*`，手机侧 `/dev/ttyGS0`）**；
3. **CDC ECM/NCM USB 网络 → SSH/日志/文件传输**；
4. eMMC、分区、ext4；
5. PMIC regulator、充电、电池状态；
6. 屏幕 simplefb 或 DRM；
7. 触摸；
8. Wi-Fi / Bluetooth；
9. 音频；
10. modem 与电话功能；
11. 摄像头、GPU 性能、休眠与日用优化。

每一个外设应独立成“资料收集 → DTS/驱动改动 → 编译 → 不上板静态验证 → 单变量上板 → 日志归档”的小任务，不能一次把多个未知节点塞入 DTS。

---

## 5. 从 6572 可以搬什么、绝不能搬什么

### 可以继承的经验与文档方法

- `CLAUDE.md` 中的细粒度 agent 分工、Haiku → Sonnet → Opus → Fable 的升级规则；
- 实质改动前备份，关键产物立即按时间戳归档；
- discover → fix → verify 的三段工作流；
- 通过 boot image header、偏移、大小、hash 做静态验证；
- 内核早期排障思想：先确认镜像入口/DT/日志路径，再推断 WDT 或驱动；
- `mainline_recon/REPORT.md` 的“驱动支持矩阵 + 缺口分析”文档结构；
- `PLAN.md` 的阶段规划模板；
- `tools/extract_boot.py`、通用 Android boot image 解包思路（先验证是否适配 R11 格式）；
- `z1_capture_mainline.sh` 的“时间戳日志 + 锁 + 元数据”模式（需重写为 R11 的实际通道）；
- `bridge_backups/` 的源、配置、产物分层归档方式。

### 绝不能直接复制为 R11 技术方案的内容

- MTK `mkbootimg --mtk` 和 MTK boot header；
- MTK Preloader、LK、ATAG、appended DTB、LineState、WDT 早停狗逻辑；
- MT6572 DTS、8250-MTK earlycon、MT6323 PMIC、MT6620/WMT Wi-Fi 及 stub headers；
- mtkclient / scatter / `bootimg` 分区名称假设；
- Z1 的 C3 UART 接线、波特率、GPIO、刷机时序；
- 任意 Z1 的 ramdisk、firmware blob、内核 `.config` 或 boot image。

---

## 6. 主要风险与停机条件

| 风险 | 为什么高 | 控制方法 |
|---|---|---|
| Bootloader 不可解锁或拒绝非签名镜像 | 可能从根本阻断 mainline 启动 | 在下载源码/改内核前先只读确认 unlock 状态与 OEM 流程 |
| 原厂镜像不完整 | 一次误刷可能失去可回滚系统 | 先备份原厂 boot/recovery/dtbo/分区表，并计算 hash |
| 无易用 TTL UART，且 USB gadget 不可用于最早期死机 | 解压或 DWC3 probe 前崩溃难以定位 | USB-first；同时启用 pstore/ramoops、保留 framebuffer/bootloader 证据，并继续寻找真实 UART pads |
| R11s DTS 缺失 | 板级节点容易猜错，尤其 PMIC/面板 | 从下游源、DTB、拆机信息逐条取证；先最小节点 |
| 显示/音频/Wi-Fi 不成熟 | 同 SoC 支持不等于手机所有外设可用 | 以 shell-first 目标推进，后置多媒体与无线 |
| 误用 R11s Plus 信息 | Plus 是 SDM835，不兼容 | 每次引用资料必须记录机型、SoC、固件版本 |

以下任一条件发生时，应停止上板，回到资料阶段：

- 无完整、经 hash 校验的原厂恢复材料；
- 不清楚 bootloader 解锁状态或启动镜像签名策略；
- 不清楚镜像写入的准确分区；
- 只有“网上有人说可刷”的方法而没有设备/版本对应关系；
- DTS 中的 regulator、内存保留区、面板、eMMC 参数来自猜测。

---

## 7. 建议在你批准后做的首轮工作包（全只读）

如果你认可方向，下一轮只做以下工作，不刷机、不解锁、不写分区：

1. 建立 R11 专属 `CLAUDE.md`、项目 memory、资料目录和备份规则；
2. 搜集并交叉验证 R11s 的官方/开源 kernel source、原厂固件入口、可用 bootloader 解锁信息；
3. 从上游 Linux 与 Redmi Note 7 DTS 提取 SDM660 最小启动依赖及 **DWC3 peripheral / QUSB2 PHY / UDC** 依赖清单；
4. 设计“R11s 硬件取证表”，明确每个 DTS 节点需要的证据，优先 USB 角色检测、PHY supplies、extcon/Type-C 与 PMIC；
5. 仅编译 upstream SDM660 参考 DTS，验证主机 arm64 工具链；
6. 输出一份“首次连接真机时只读要采什么、哪些命令不能运行”的操作清单，特别确认原厂 USB gadget 枚举和 bootloader 状态，等待你逐项确认。

此阶段结束后，再提交一份基于**真实 R11s 原厂镜像和 bootloader 状态**的启动设计，供你明确批准是否制作临时测试镜像。

---

## 8. 资料来源（初步）

- Linux 主线：[`sdm660.dtsi`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/arch/arm64/boot/dts/qcom/sdm660.dtsi?h=master)
- Linux 主线：[`sdm630.dtsi`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/arch/arm64/boot/dts/qcom/sdm630.dtsi?h=master)
- Linux 主线：[`sdm660-xiaomi-lavender.dts`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/arch/arm64/boot/dts/qcom/sdm660-xiaomi-lavender.dts?h=master)
- SDM660 上游导入提交：[`feec34411d4c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/arch/arm64/boot/dts/qcom/sdm660.dtsi?id=feec34411d4c0a9759106ef4f7d563438b3881ae)
- R11s 外观规格交叉参考：[GSMArena R11s](https://www.gsmarena.com/oppo_r11s-9011.php)
- 6572 经验源：`/home/<user>/claude/6572/CLAUDE.md`、`PLAN.md`、`mainline_recon/REPORT.md`、`mainline_recon/BUILD_Z1_REPORT.md`。

> 初步 web 调研中存在彼此不完全一致的外部规格信息；本文没有将其当作能直接写入 DTS 的硬件事实。下一步应以手中 R11s 的固件、下游 DTS 和只读取证为准。
