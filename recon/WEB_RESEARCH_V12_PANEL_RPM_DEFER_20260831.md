# v12 面板问题 web 研究:qcom_smd-regulator defer 机制(2026-08-31)
> 来源: workflow wf_cc891569-4c7 agent web-rpm-defer。基于 torvalds/linux master 源码逐条核实。

## Executive answer

**(a)** `qcom,rpm-pm660-regulators` (CONFIG_REGULATOR_QCOM_SMD_RPM, driver `drivers/regulator/qcom_smd-regulator.c`) is not a normal platform device you can defer on forever in isolation: the node is a **grandchild of the `rpm-requests` rpmsg device**, and the platform device is created only when the RPM-side glink channel `"rpm_requests"` opens. Consumers requesting one of its supplies get `-EPROBE_DEFER` because the DT lookup resolves `-ENODEV` ("node present, no registered regulator"), which the regulator core converts to a retry loop. If the channel never opens, panel/MDP/DWC3 consumers defer indefinitely (a timeout converts them to `-ETIMEDOUT`, but that only happens after `deferred_probe_timeout`, default 10s with CONFIG_MODULES).

**(b)** On SDM660 the RPM is not started by the Linux kernel. The kernel has **no remoteproc that loads RPM firmware for RPM-SMD platforms** (`qcom,sdm660-rpm-proc` binds the plain `qcom,rpm-proc` platform driver `drivers/soc/qcom/rpm-proc.c`, which only populates children and registers an smd-edge if present — verified from upstream source and the original patch text). Therefore, on a rescue initramfs with no `/lib/firmware`:

- **If the ToC (table of contents) in the RPM message RAM at 0x778000 is intact and RPM is already running** (which is the normal case on SDM660 — XBL/APDP started it before the kernel), the pm660 RPM regulators **will register**, and the absence of `/lib/firmware` in the initramfs is irrelevant to RPM at all. This is how every postmarketOS SDM660 device boots its initramfs with working RPM regulators, clocks (rpmcc) and rpmpd.
- **If the ToC is missing/corrupt or RPM never started**, `qcom,glink-rpm` probe fails early (`glink_rpm_parse_toc` error), the `rpm_requests` device is never created, the regulators **never register**, and everything consuming them stays deferred. Nothing in userspace can fix this, because the kernel has no mechanism to boot the RPM on this generation.

**Upstream-correct fallback:** (1) `regulator-fixed` nodes for supplies you know the firmware left on; (2) do **not** switch to SPMI `qcom,pm660-regulators` as a replacement — on SDM660 the hardware control of these rails is owned by the RPM firmware; the SPMI tables exist upstream but mainline SDM660 DTSes deliberately put the regulators under `&rpm_requests`. The real gate to investigate is **why the glink edge / channel did not come up**, not the regulator driver.

---

## (a) qcom_smd-regulator probe ordering — mechanism, verified from upstream source (torvalds/linux master)

### The dependency chain for SDM660, top-down

1. **`qcom,sdm660-rpm-proc` ("qcom,rpm-proc")** → `drivers/soc/qcom/rpm-proc.c` (author Stephan Gerhold). Verified from source: `rpm_proc_probe()` optionally registers an `smd-edge` (not used on sdm660, which has `glink-edge`) and calls `devm_of_platform_populate(dev)` to create child platform devices. No firmware loading happens here. URL: https://github.com/torvalds/linux/blob/master/drivers/soc/qcom/rpm-proc.c ; original patch: https://lkml.indiana.edu/2306.0/03913.html
2. **`qcom,glink-rpm`** (glink-edge child) → `drivers/rpmsg/qcom_glink_rpm.c`. Verified from source: `glink_rpm_probe()` iomaps `qcom,rpm-msg-ram` (0x778000 on sdm660), then calls `glink_rpm_parse_toc()`. **If the ToC is not there, probe returns an error immediately** — no rpm_requests device ever exists. On success it requests a mailbox channel (`mboxes = <&apcs_glb 0>` → `qcom,sdm660-apcs-hmss-global` handled by `drivers/mailbox/qcom-apcs-ipc-mailbox.c`, verified compatible entry), sets up `qcom_glink_native_probe()` and enables the IRQ. URL: https://github.com/torvalds/linux/blob/master/drivers/rpmsg/qcom_glink_rpm.c
3. **The `rpm_requests` rpmsg device is created remotely-opened.** Verified from `drivers/rpmsg/qcom_glink_native.c` (`qcom_glink_rx_open` ≈ line 1640-1705): when a channel-open message arrives from RPM, the code matches `qcom,glink-channels = "rpm_requests"`, allocates the channel, creates the rpmsg_device with `rpdev->dev.parent = glink->dev` and `of_node = rpm-requests node`, then `rpmsg_register_device()`. So the device's very existence and parent linkage are a **runtime event dependent on the RPM side opening the channel**. URL: https://github.com/torvalds/linux/blob/master/drivers/rpmsg/qcom_glink_native.c
4. **`qcom,rpm-sdm660` / `qcom,glink-smd-rpm`** → `drivers/soc/qcom/smd-rpm.c` (rpmsg_driver). Verified from source: `qcom_smd_rpm_probe()` stashes the rpmsg endpoint in drvdata and calls `of_platform_populate(rpdev->dev.of_node, ...)` — this is the moment when `rpmcc`, `rpmpd` and the `regulators` child **platform devices are instantiated**, with parent = the rpmsg device. Note the old-style `arch_initcall(qcom_smd_rpm_init)` registration. URL: https://github.com/torvalds/linux/blob/master/drivers/soc/qcom/smd-rpm.c
5. **`qcom,rpm-pm660-regulators`** → `drivers/regulator/qcom_smd-regulator.c` (platform_driver, `.probe_type = PROBE_PREFER_ASYNCHRONOUS`, `subsys_initcall` registration). Verified from source: `rpm_reg_probe()` does `rpm = dev_get_drvdata(pdev->dev.parent); if (!rpm) return -ENODEV;` — i.e. it structurally requires the smd-rpm rpmsg device to have probed first; there is **no -EPROBE_DEFER in this driver at all** (the parent is guaranteed by construction). Then it registers each vreg via `devm_regulator_register()`. Also note the **global static `smd_vreg_rpm`** singleton (one RPM handle for the whole driver) and that the pm660/pm660l tables were added by kholk11's series (commits `6d849653b00f` "regulator: qcom_smd: Add PM660/PM660L regulator support" and `0074c4472dcb` for the SPMI twin). URLs: https://github.com/torvalds/linux/blob/master/drivers/regulator/qcom_smd-regulator.c ; https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2010.0/01196.html ; LWN history: https://lwn.net/Articles/658204/ ; https://groups.google.com/g/fa.linux.kernel/c/0bfi0qPoc_w

Verified mainline DT topology (sdm630.dtsi = shared SDM630/660 SoC DTS):
```
rpm: remoteproc { compatible = "qcom,sdm660-rpm-proc", "qcom,rpm-proc";
  glink-edge { compatible = "qcom,glink-rpm";
    interrupts = <GIC_SPI 168 ...>; qcom,rpm-msg-ram = <&rpm_msg_ram>; mboxes = <&apcs_glb 0>;
    rpm_requests: rpm-requests { compatible = "qcom,rpm-sdm660", "qcom,glink-smd-rpm";
      qcom,glink-channels = "rpm_requests";
      rpmcc, rpmpd, (board DTS adds pm660l/pm660 regulator nodes here) } } }
```
URLs: https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/sdm630.dtsi (lines ~365-430, msg-ram at 587: `rpm_msg_ram: sram@778000`), board example https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/sdm660-xiaomi-lavender.dts (regulators-0/-1 under `&rpm_requests`).

### How consumers defer

Verified from `drivers/regulator/core.c`:
- `regulator_dt_lookup()` → `of_regulator_dev_lookup()`: the `-supply` phandle resolves to a DT node, but if no regulator is registered for that node it returns **`-ENODEV`** (documented in `regulator_dev_lookup()` comment: "-%ENODEV if lookup fails permanently, -%EPROBE_DEFER if lookup could succeed in the future").
- In `_regulator_get_common()`, when lookup fails and the DT phandle did point at a node, the failure is converted to **`-EPROBE_DEFER`** (consumer retries), NOT to the "dummy regulator" fallback (dummy substitution only applies when there was no node match at all and constraints are incomplete — verified lines ~2440-2460). So a panel's `vddio-supply = <&vreg_l10a_1p8>` where `vreg_l10a_1p8` lives under a not-yet-probed rpm regulators node **defers**.

Verified from `drivers/base/dd.c` (deferred-probe machinery):
- Every probe attempt re-triggers the deferred workqueue (`driver_deferred_probe_trigger`), so the panel retries on every successful probe elsewhere — but **if the rpm_requests chain never completes, there is nothing that ever produces its supply**.
- `CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT`: `default 0 if !MODULES, default 10 if MODULES` (drivers/base/Kconfig). After `deferred_probe_initcall`, if the timeout is set, `deferred_probe_timeout_work_func()` calls `fw_devlink_drivers_done()` and `driver_deferred_probe_check_state()` starts returning `-ETIMEDOUT` for still-deferred devices; before that it returns `-EPROBE_DEFER` forever. Boot param: `deferred_probe_timeout=N`. The work also **prints every still-pending deferred device with reason** (`"deferred probe pending: ..."`), which is exactly the dmesg signature of a dead RPM edge.
- `deferred_probe_timeout=` param and `driver_deferred_probe_check_state()` semantics: https://github.com/torvalds/linux/blob/master/drivers/base/dd.c

### Known cases where consumers defer forever

- postmarketOS sdm660 platform page (display bring-up context): https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_660/630/636_(SDM660/SDM630/SDM636)
- Practical writeup of exactly this failure mode (panel/display supplies, "make sure fixed-regulator is enabled, mysterious deferred probes"): https://knuxify.github.io/blog/2023/04/tab3-display.html
- Classic reference on complex defer chains (every probe re-triggers all deferred devices): Andrzej Hajda, ELC 2017 PDF, https://events19.linuxfoundation.org/wp-content/uploads/2017/12/Deferred-Problem-Issues-With-Complex-Dependencies-Between-Devices-in-Linux-Kernel.pdf
- msm8916-mainline has hit analogous rpm/smd ordering issues repeatedly (their panel generator docs discuss regulator gating of panels): https://github.com/msm8916-mainline/linux-mdss-dsi-panel-driver-generator

---

## (b) Does qcom,rpm-pm660-regulators need RPM running? What if RPM firmware never loads?

**Verified facts:**

1. SDM660 uses **RPM over glink-SMD**, not RPMh. `qcom,pm660-rpmh-regulators` does exist in `qcom-rpmh-regulator.c` (for PMIC-on-RPMh platforms; probe depends on `cmd_db_read_addr()` → `-ENODEV` if cmd-db missing: https://github.com/torvalds/linux/blob/master/drivers/regulator/qcom-rpmh-regulator.c line ~531), but **no mainline SDM660 DTS uses it**. sdm630.dtsi and sdm660-xiaomi-lavender.dts use `qcom,rpm-pm660(l)-regulators` under rpm_requests. (Verified by grepping both files.)
2. The kernel never boots RPM on these SoCs. The rpm-proc patch states explicitly: *"The RPM firmware is usually already loaded and started by earlier components in the boot chain and is not meant to be ever restarted."* (https://lkml.indiana.edu/2306.0/03913.html ; source: rpm-proc.c has no rproc_start).
3. Therefore `/lib/firmware` content is irrelevant to RPM on SDM660. A minimal rescue initramfs without it does not affect RPM regulators **as long as RPM was already started by the boot chain**. Evidence this works in practice: postmarketOS sdm660 kernels boot initramfs shells with RPM regulators/rpmcc/rpmpd active (platform page + sdm660-mainline tree: https://github.com/sdm660-mainline/linux ; Linaro's mainline-boot guide for Qualcomm uses exactly this minimal-initramfs flow: https://www.linaro.org/blog/let-s-boot-the-mainline-linux-kernel-on-qualcomm-devices).
4. Qualcomm boot-chain documentation: XBL "initializes the hardware, firmware images, ... PMIC, and DDR" (https://docs.qualcomm.com/doc/80-80021-4/topic/bootloader.html ; https://docs.qualcomm.com/doc/80-70029-3/topic/boot-flow-and-architecture-overview.html). Third-party: XBL loads TrustZone + RPM/AOP firmware before the kernel (https://squadri.me/posts/Android-Boot-Sequence-1). LineageOS chain-of-trust describes SBL/XBL bringing up "core processes ... such as TrustZone" (https://lineageos.org/engineering/Qualcomm-Firmware).

**Inference (high confidence):** On the R11s, RPM starts between XBL and ABL as part of the stock boot chain; nothing the rescue kernel does (or omits) can start or restart it. So "PM660 RPM regulators never register in the rescue initramfs" can only mean: (i) the ToC parse failed (rpm-msg-ram not mapped/populated → `qcom,glink-rpm` probe error at boot, very early in dmesg), (ii) the IRQ/mailbox never signaled the channel open (RPM dead or handoff state lost), or (iii) a missing/broken config (CONFIG_QCOM_GLINK_RPM / mailbox driver) — not a firmware-loading problem.

**Direct answer to the key question:** On a minimal initramfs boot where the RPM edge never comes up, **no, the pm660 RPM regulators will never register**, and userspace has no lever to fix it on SDM660 (nothing to `request_firmware`, no remoteproc to boot). Diagnostics: check dmesg for `qcom,glink-rpm` ToC errors, `cat /sys/kernel/debug/devices_deferred`, watch for the `deferred probe pending:` dump after the timeout, and check whether `rpm_requests` appears in `/sys/bus/rpmsg/devices/`.

**Upstream-correct fallback options (verified):**

1. **`regulator-fixed` for known-on rails** — this is what mainline SDM660 board DTSes already do for non-RPM supplies (lavender.dts has a fixed regulator node; verified). Suitable for a minimal debug DT: describe only the rails you need (e.g., a model of the panel supply) as fixed, matching the voltages firmware left enabled.
2. **Do NOT substitute `qcom,pm660-regulators` (SPMI, CONFIG_REGULATOR_QCOM_SPMI)** even though it exists upstream with full pm660/pm660l tables (`drivers/regulator/qcom_spmi-regulator.c`, compatibles verified at lines 2475-2476; pm660.dtsi has a `pm660_spmi_regulators` node). On SDM660 the actual rail ownership lives with the RPM firmware (SMD RPM resources `LDOA/SMPS`, verified in qcom_smd-regulator.c tables). Bypassing RPM via SPMI while RPM firmware holds active votes risks inconsistent hardware state and is not how any upstream SDM660 DTS is built. Mainline precedent on this exact family: msm8916/msm8998/lavender all use the RPM-path regulators.
3. **The correct fix for "panel defers forever" is to make the RPM edge come up** — verify CONFIG_QCOM_APCS_IPC (mailbox), CONFIG_QCOM_GLINK_RPM (or =m with the modules actually present in the initramfs), CONFIG_QCOM_SMD_RPM, CONFIG_REGULATOR_QCOM_SMD_RPM are all built-in or available, and that the DT rpm node matches `sdm630.dtsi` (msg-ram phandle, irq 168, apcs_glb). If those are right and the channel still never opens, that is a firmware/handoff problem outside the kernel's control — fall back to option 1 and keep the display off the critical path, consistent with the project's USB-first gating.

### Facts vs inference — summary
- **Facts (read from torvalds/linux master + LKML archives):** entire probe chain above (rpm-proc.c, qcom_glink_rpm.c ToC gate, qcom_glink_native.c remote-open, smd-rpm.c of_platform_populate, qcom_smd-regulator.c parent-drvdata requirement, regulator-core -ENODEV→-EPROBE_DEFER, dd.c timeout machinery, Kconfig defaults, sdm630/lavender/pm660 DTS topology, SPMI vs RPMh driver compatibles).
- **Facts (vendor/community docs):** XBL initializes firmware images incl. PMIC before kernel; rpm-proc patch statement that RPM is started by boot chain; postmarketOS sdm660 boots with RPM regulators in initramfs.
- **Inference:** R11s-specific RPM start point (between XBL and ABL) is inferred from generic Qualcomm boot docs + sdm660 platform behavior; the claim that "SPMI bypass risks inconsistent state" is engineering inference (RPM firmware holds its own votes; no public upstream incident cited).
