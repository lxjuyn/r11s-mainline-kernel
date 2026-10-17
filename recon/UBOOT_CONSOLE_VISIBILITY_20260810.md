# U-Boot Console 可见性 — 取证记录

> Timestamp: 2026-08-10 02:0x
> 来源: workflow whrcb4lue (2 sonnet agents, 83k tokens)。fork 源码验证。

## 关键结论: 当前挂起在 board_r 之前, 主机侧不可见

- USB gadget (usbacm) 枚举严格发生在 board_r console_init_r。
  "卡 1 屏" 在 USB init 之前 -> **usbacm 抓不到当前挂起**。
- ramoops (CONSOLE_RAMOOPS) 与 usbacm 同时 (console_init_r) 启动 -> 同样错过挂起窗口。
- console_record INIT_F (0x400, board_f) 可能存 board_f 文本, 但需同 boot 到达 fastboot
  (`fastboot oem console`) 才能读, 挂起时不可达。记录易失 (malloc buffer, reset 丢)。
- **唯一可观测标记**:
  - splash framebuffer banner 在 stdio_init_tables 绘制 (console_init_r 前一步):
    - 屏上有 U-Boot banner -> just-past-stdio, ACM 缺 = DWC3 失败
    - 屏上无任何 U-Boot 文本 (只有 OPPO logo) -> pre-board_r
  - 需用户看手机屏幕确认。

## usbacm 默认 (若想 tethered)

- env 改 qcom-sdm660-phone.env: stdin/stdout/stderr 加 usbacm。
- fallback 安全 (iomux continue past start() 失败)。
- **Caveat**: USB init 成功后 acm_stdio_start busy-loop 等 host 打开 ACM 端口 ->
  每次 boot 在 console_init_r 卡住直到 host 连。仅 tethered 观察用。

## ramoops 激活 (CONSOLE_RAMOOPS)

- 需 CONFIG_CONSOLE_RAMOOPS=y + DTS ramoops@a0000000 (4MiB, compatible "ramoops",
  record-size 0, console-size 0x200000, pmsg-size 0x200000)。
- 0xa0000000 经 FORK_DTS_AUDIT 验证真空闲。输出经 persistent_ram 跨 warm reset 存活,
  后可由 Linux pstore 读。但只覆盖 console_init_r 之后 -> 对当前挂起无效。

## 对诊断的含义

U-Boot 卡 1 屏 = pre-board_r。要定位需要:
1. **用户看屏幕**: 有无 U-Boot banner (区分 pre-board_r vs DWC3 失败)。
2. wf4o5drjr (hang deep) 的 board_f 深层分析 (进行中)。
3. 无法用 USB/ramoops 抓 pre-board_r 输出。
