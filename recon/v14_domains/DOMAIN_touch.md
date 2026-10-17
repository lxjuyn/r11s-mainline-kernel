# DOMAIN_touch — 触摸域（rmi4 / s3508 F12）

> Wave 1 · 子代理只读取证 · 2026-09-02 · 完整证据链见 `LEDGER_v14_20260902.md` F01-F03

## 结论

1. **-95 不是"适配器不支持块读"**：`rmi_i2c_read_block` 发的第二笔消息 `len == 0`（零长读），被 i2c core 的 `I2C_AQ_NO_ZERO_LEN` quirk 在 `master_xfer` **之前**拒绝。
2. **传输层写法无需改**：`rmi_i2c.c:176-199` 已是标准「一笔 `i2c_transfer` + 两条消息」写法，不是 SMBus 块读；零长读止步于 core，总线上 **0 个 SCL 周期**。
3. **零长读源头在 `rmi_driver.c:887`**：用 `size_presence_reg` 当长度，实机 F12 Control 描述符首字节读出 `0x00`（日志 `@004b: 00 00 00 00`），于是发出 `len=0`；`rmi_i2c.c:207-210` 再把 -95 吞成 -EIO(-5)。
4. **无限闭环 = `rmi_f12_probe` 的三处 `return -EPROBE_DEFER`**，deferred probe 对同一设备**无重试次数上限**，而"等传感器稳定"在本机永远不成立 → 每 704–727ms 重入一次，永不停止。
5. **危害**：每轮占用 `deferred_probe_work` 约 680ms（**占空比 82–96%**），该 work 全局串行，会饿死同队列其他所有 deferred 设备。

## 证据

**零长读被 core 拒绝（决定性）** — 实机日志 `:403-421`
```
[    1.786049] i2c i2c-0: adapter quirk: no zero length (addr 0x0020, size 0, read)
[    1.786083] rmi4_i2c 0-0020: rmi_i2c_read_block: read failed, retry 1: -95.
（共 10 次，间隔恒定 23.4/24.0 ms）
```

**-95 产生点（在 master_xfer 之前）** — `drivers/i2c/i2c-core-base.c:2147-2152`、`:2226-2239`
```c
dev_err_ratelimited(&adap->dev, "adapter quirk: %s (addr 0x%04x, size %u, %s)\n", ...);
return -EOPNOTSUPP;
...
if (adap->quirks && i2c_check_for_quirks(adap, msgs, num))
        return -EOPNOTSUPP;                    /* ← 本例命中 */
```

**零长读的发起者** — `drivers/input/rmi4/rmi_driver.c:872-889`
```c
ret = rmi_read(d, addr, &size_presence_reg);
if (ret) return ret;
++addr;
if (size_presence_reg < 0 || size_presence_reg > 35)   /* u8，'<0' 恒假：死代码 */
        return -EIO;
...
ret = rmi_read_block(d, addr, buf, size_presence_reg);  /* ← 887：len=0 → -95 */
```

**-95 被吞成 -5** — `drivers/input/rmi4/rmi_i2c.c:198-210`
```c
for (retry = 0; retry < RMI_I2C_RETRY_TIMES; retry++) {   /* 10 次 */
        retval = i2c_transfer(client->adapter, msgs, ARRAY_SIZE(msgs));
        if (retval == ARRAY_SIZE(msgs)) break;
        ... msleep(RMI_I2C_RETRY_DELAY_MS);               /* 20ms */
}
if (retry == RMI_I2C_RETRY_TIMES) { ... retval = -EIO; }  /* ← -95 → -5 */
```

**无限闭环三要素** — `drivers/input/rmi4/rmi_f12.c`
- `:370` — `for (attempt = 0; attempt < 2; attempt++)`（上限 2）
- `:386-402` — 软复位命令 `RMI_F12_SOFT_RESET_CMD` + `msleep(RMI_F12_SETTLE_DELAY_MS)`（200ms）
- `:470 / 480 / 490` — Query / Control / Data 三处 `return -EPROBE_DEFER;`（**实机命中 480**）

**周期量化（用日志时间戳算）**
```
deferring probe 时间戳：2.469540 / 3.293589 / 4.653870 / 5.357768 / 6.061711 / 6.788847
间隔(ms)：824.0 / 1360.3 / 703.9 / 703.9 / 727.1  → 稳态 ≈ 704-727 ms/轮
轮内分解：2×(10×24ms 重试) + 1×200ms settle ≈ 680ms，占稳态周期 94%
总线占用 0（20 次失败读均未进 master_xfer）；CPU ≈ 10% 单核
```

**调用链** — `rmi_driver.c:1188-1208`
```
rmi_driver_probe(1472) → rmi_scan_pdt(rmi_count_irqs,1378) → rmi_create_function(1126/1431-1442)
  → rmi_register_function(1188) → device_add → rmi_f12_probe(409)
  → rmi_scan_pdt(rmi_initial_reset,1529) → devm_input_allocate_device(1609) → input_register_device(1636)
```
`rmi_register_function` 对单函数失败有容错（`RMI_SCAN_CONTINUE`），倾向 input 设备仍会注册（未直接证实）。

## 补丁级定位

| 项 | 位置 | 改法 | 收益 | 风险 |
|---|---|---|---|---|
| **A-1 治本** | `rmi_driver.c:877`、`:887` | 删 `< 0` 死代码；`if (size_presence_reg == 0) return -ENODEV;` | -95 与 200ms 徒劳重试立即消失 | 影响所有 Fxx 描述符解析（size==0 按规范即"无该描述符"） |
| **A-2 刹车** | `rmi_f12.c:470/480/490` | 模块级计数器 helper，超 3 次返回 `-ENODEV` 不再 defer | 最多 3 轮后停止；解除工作队列占用 | **放弃后 fn12 仍在 function_list 且 irq 位已置位，需复核 `rmi_f12_attention()` 空 drvdata 风险** |
| **A-3 清理** | `rmi_i2c.c:198` | `if (!len) return -EINVAL;`；`-EOPNOTSUPP` 不重试 | 每轮省 2×200ms，日志减半 | 极低 |

## 未取证

- `i2c-0` 适配器驱动与 quirk 声明位置（未打开 `drivers/i2c/busses/`）
- `rmi_f12_attention()` **未读** → A-2 放弃路径的 IRQ/空 drvdata 风险未证实
- F12 probe 失败是否导致 input 设备不注册 —— 仅有间接证据（倾向不会）
- 日志 `:404` 之前（<1.786s）的首次 probe 完整序列未读

## 与既有事实的冲突

1. **代码注释 vs 实机**（`rmi_f12.c:342-354`）：注释称"descriptor 区读出垃圾 → size>35 → -EIO，~100µs 内失败、无 I2C 错误"；实测首字节是 **0x00（不是 >35）**，走 `size==0` 分支，且**确实产生 -95**，单次耗时 **240ms 而非 100µs**。→ 该"软复位 + 重试 + defer"策略对本机场景完全无效且放大危害。
2. **-95 vs -5 口径差**：f12 打印 -5 掩盖了底层 -95，定位时必须看 `rmi4_i2c` 行与 `adapter quirk` 行。
