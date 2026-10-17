# R11s 资料与证据目录

本目录只保存可追溯的资料、调研输出和取证报告。每份报告必须区分：

- **已证实：**给出 URL、文件 hash、源文件路径/行号或原厂镜像偏移；
- **推断：**说明推断链及适用范围；
- **未知：**不得以参考机型代替；
- **错误/污染资料：**记录为何排除，避免以后误用。

## 推荐文件

- `DEVICE_IDENTITY.md`：实际型号、SoC、firmware、bootloader 状态。
- `FACTORY_ARTIFACT_MANIFEST.md`：原厂文件、来源、SHA-256、用途、回滚关系。
- `BOOT_IMAGE_ANALYSIS.md`：原厂 boot/recovery/dtbo 格式与打包事实。
- `SDM660_UPSTREAM_MAP.md`：上游 DTS 与驱动支持矩阵。
- `R11S_DTS_EVIDENCE.md`：每个 R11s 节点的下游/原厂来源。
- `USB_FIRST_PLAN.md`：DWC3、PHY、UDC、ACM/ECM/NCM、PC 日志链路。
- `EARLY_LOGGING_PLAN.md`：USB 之前的 pstore/ramoops/framebuffer 证据策略。
- `RESEARCH_REJECTIONS.md`：混淆 MTK、R11、R11s Plus 或无一手来源的资料。

没有证据的内容不能进入可测试 DTS 或打包命令。
