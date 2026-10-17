## Executive
 answer

**(a
)**
 `qcom,r
pm
-pm66
0-regulators`
 (CONFIG_REGULATOR
_QCOM
_SMD_RPM
, driver `drivers
/regulator
/qcom_smd
-regulator.c`)
 is not a normal
 platform device you can
 defer
 on forever in isolation
: the
 node is a **
grandchild of the
 `
rpm-requests`
 rpmsg device**,
 and the platform device
 is created
 only when the RPM
-side
 glink channel `"
rpm_requests"` opens
. Consumers requesting one
 of its supplies get
 `-EPROBE
_DEFER` because
 the DT lookup resolves
 `-ENODEV`
 ("
node present, no
 registered regulator"), which
 the regulator core converts
 to a retry loop
. If the channel
 never opens, panel
/MDP/D
WC3 consumers defer
 indefinitely
 (a timeout converts
 them to `-ET
IMEDOUT`,
 but that only happens
 after
 `deferred_probe
_timeout`,
 default 10
s with CONFIG_MODULES
).


**(b)**
 On SDM66
0 the RPM is
 not started by the
 Linux
 kernel. The kernel
 has **no remot
eproc
 that loads RPM firmware
 for
 RPM-SMD platforms
** (`
qcom,sdm
660
-rpm-proc
` binds the plain
 `qcom,r
pm-proc`
 platform driver `drivers
/soc/q
com/rpm-pro
c.c`, which
 only populates children
 and registers an sm
d-edge if present
 —
 verified from upstream source
 and the original
 patch text). Therefore
, on a rescue
 initramfs with
 no `/lib/f
irmware`:

-
 **
If the ToC
 (table of
 contents) in the
 RPM message RAM at
 0x7
7800
0 is intact and
 RPM is already running
**
 (which is the
 normal case
 on SDM66
0 —
 XBL/APDP
 started it before the
 kernel
), the pm6
60 RPM
 regulators **will register
**, and the absence
 of `/lib
/firmware` in
 the initramfs
 is irrelevant to RPM
 at all. This
 is how every post
marketOS SDM6
60 device
 boots its initram
fs with
 working RPM regulators,
 clocks (rpmcc
)
 and rpmpd
.
- **
If the ToC
 is missing
/corrupt or
 RPM never started**,
 `q
com,glink-r
pm`
 probe fails early (`
glink_r
pm_parse_toc
` error), the
 `rpm
_requests` device is
 never created, the
 regulators **never register
**, and
 everything consuming them stays
 deferred. Nothing in
 users
pace can fix this
, because the kernel
 has
 no mechanism to boot
 the RPM on this
 generation
.

**Up
stream-correct
 fallback:** (1
) `
regulator-fixed`
 nodes for supplies you
 know the firmware left
 on;
 (2) do
 **not** switch
 to SPMI
 `
qcom,pm
660
-regulators` as
 a replacement — on
 SDM660
 the hardware control of
 these
 rails is owned by
 the
 RPM firmware; the
 SPMI tables
 exist upstream but main
line SDM66
0 D
TSes deliberately put
 the regulators under `
&rpm_requests`.
 The real gate to
 investigate is **why
 the glink
 edge / channel did
 not come
 up**, not the
 regulator
 driver.

---


## (a
) qcom_s
md-reg
ulator probe ordering —
 mechanism, verified from
 upstream
 source (torval
ds/linux
 master)

###
 The
 dependency chain for SDM
660
, top-down


1
. **`q
com,sdm6
60
-rpm-proc
` ("qcom
,rpm
-proc")**
 → `drivers/s
oc
/qcom/rpm
-proc.c`
 (author Stephan Ger
hold).
 Verified from source:
 `
rpm_proc_probe()`
 optionally registers an `
s
md-edge` (
not used on sdm
660,
 which has `g
link-edge`)
 and calls `dev
m_of_platform_pop
ulate(dev)` to
 create child
 platform devices. No
 firmware loading happens here
. URL
: https://github
.com/torval
ds/linux/blob/master
/drivers/soc/q
com/rpm-pro
c.c ; original
 patch: https://
lkml.indiana
.edu/23
06.0
/039
13.html

2. **`
qcom,glink
-rpm`**
 (glink-edge
 child)
 → `drivers/r
pmsg/qcom
_glink_rpm
.c`. Verified from
 source: `g
link
_rpm_probe()`
 iomaps `
qcom
,rpm-msg-
ram` (0
x778
000 on
 sdm660
), then
 calls `glink
_r
pm_parse_toc
()`. **If
 the
 ToC is not
 there, probe returns
 an
 error immediately** —
 no
 rpm_requests device ever
 exists. On success
 it requests a
 mailbox channel (`m
boxes = 
<&apcs_g
lb 0>`
 → `qcom
,s
dm660
-apcs-hm
ss-global` handled
 by `drivers/mail
box/qcom-ap
cs-ipc-mail
box.c`, verified
 compatible entry), sets
 up `qcom
_glink
_native_probe()` and
 enables
 the IRQ. URL
: https://github
.com/torval
ds/linux/blob/master
/drivers/rpmsg
/qcom_glink
_rpm.c

3. **The
 `rpm_requests`
 rpmsg device is
 created remotely-opened
.** Verified
 from `drivers/r
pmsg
/qcom_glink
_native.c` (`
qcom_g
link_rx_open`
 ≈ line 1
6
40-1
705
): when a channel
-open message arrives from
 RPM, the code
 matches `qcom
,g
link-channels =
 "rpm_requests"
`, allocates the
 channel, creates the
 rpmsg_device
 with `rpdev
->dev.parent =
 glink->dev
` and `of
_node = rpm-
requests node
`, then `rp
msg_register_device()
`. So the device
's very existence and
 parent linkage are a
 **runtime event dependent
 on the RPM side
 opening the channel**.
 URL
: https://github
.com/torval
ds/linux/blob/master
/drivers/rpmsg
/qcom_glink
_native.c
4
. **`q
com,rpm-s
dm660
` / `q
com,g
link-smd-r
pm`** →
 `drivers/soc
/qcom/smd
-rpm.c`
 (rpmsg_driver
). Verified from source
: `qcom
_smd_rpm
_probe()` stashes
 the rpmsg
 endpoint in drvdata
 and calls `
of_platform_populate
(rpdev->dev
.of_node, ...
)` — this is
 the moment when `
rpmcc`, `
rp
mpd` and
 the `reg
ulators` child **
platform devices are instantiated
**, with parent =
 the
 rpmsg device.
 Note the old-style
 `arch_initcall
(q
com_smd_r
pm_init)` registration
. URL: https
://github.com/t
orvalds/linux
/blob/master/drivers/s
oc/qcom/s
md-rpm.c

5. **
`qcom,r
pm-pm6
60-regulators
`** → `
drivers/regulator/q
com_smd-reg
ulator.c` (
platform
_driver, `.probe
_type = PRO
BE_PREFER_A
SYNCHRON
OUS`, `sub
sys_initcall`
 registration). Verified from
 source: `rpm
_reg_probe()` does
 `rpm = dev
_get_drvdata(pdev->
dev.parent); if
 (!rpm) return
 -ENODEV;
` — i.e
. it struct
urally requires the sm
d-rpm rp
msg device to have
 probed first;
 there is **no
 -EPRO
BE_DEFER in
 this driver at all
** (
the parent is guaranteed
 by construction). Then
 it registers each v
reg via `dev
m_regulator_register
()`. Also note
 the **
global static `s
md_vreg_r
pm`** singleton
 (one RPM handle
 for the whole driver
)
 and that the pm
660/pm
660l
 tables were added by
 k
holk11
's series (comm
its `6d
84
9653
b00f
` "regulator
: qcom_s
md: Add PM
660/
PM660
L regulator support"
 and `00
74c
4472
dcb` for
 the SPMI
 twin). URLs:
 https://github
.com/torval
ds/linux/blob/master
/drivers/regulator/q
com_smd-reg
ulator.c ; https
://lkml.res
cloud.iu.edu
/hypermail/linux
/kernel/20
10.0
/011
96.html ;
 LWN history:
 https://l
wn.net/Articles
/658
204/
 ; https://groups
.google.com/g/fa
.linux.kernel/c
/0bfi
0qPoc
_w

Verified main
line DT topology (
sdm63
0
.dtsi =
 shared SDM63
0/66
0 SoC D
TS):
```

rpm:
 remoteproc {
 compatible = "q
com
,sdm66
0-rpm-pro
c", "q
com,r
pm-proc";

  glink
-edge { compatible =
 "qcom,g
link-rpm";

    interrupts =
 <GIC_SPI
 168
 ...>; qcom
,rpm-msg-
ram = <&
rpm_msg_ram>;
 mboxes = 
<&apcs_g
lb 0>;

    rpm_requests
: rpm-requests
 { compatible = "
qcom,rpm
-sdm66
0", "q
com,glink-s
md-rpm";

      qcom
,glink-channels
 = "rpm_requests
";
      rpm
cc, rpmp
d,
 (board DTS
 adds pm
660l
/pm660
 regulator nodes here)
 }
 } }
```

URL
s: https://
github
.com/torval
ds/linux/blob/master
/arch/arm64
/boot/dts/q
com/sdm6
30.dts
i (lines ~
36
5-43
0,
 msg-ram at
 587
: `rpm_msg
_ram
: sram@
7780
00`),
 board example https://
github.com/t
orvalds/linux
/blob/master/arch/arm
64/boot/d
ts/qcom/s
dm660
-xiaomi-l
avender.dts
 (regulators-
0
/-1 under `
&rpm_requests
`).

### How
 consumers defer

Verified
 from `drivers/reg
ulator/core.c`:

- `reg
ulator_dt_lookup()`
 → `of_reg
ulator_dev_lookup()
`: the `-supply
` phandle
 resolves to a DT
 node, but if
 no
 regulator is registered for
 that node
 it returns **`
-ENODEV`
** (documented
 in
 `regulator_dev
_lookup
()` comment: "-
%ENODEV if
 lookup
 fails permanently, -
%EPROBE
_DEFER if lookup
 could succeed in the
 future").
-
 In `_regulator
_get
_common()`, when
 lookup fails and the
 DT
 phandle did point
 at a node
, the failure is
 converted
 to **`-
EPRO
BE_DEFER`
** (consumer retries
), NOT to the
 "
dummy regulator" fallback
 (dummy substitution only
 applies when there
 was no node match
 at all and constraints
 are incomplete — verified
 lines ~24
4
0-24
60). So
 a
 panel's `v
ddio
-supply = 
<&vreg_l
10
a_1p
8>` where `
vreg_l1
0a_1
p8` lives
 under a not-y
et-pro
bed rpm regulators node
 **
defers**.


Verified from `drivers
/base/dd.c`
 (deferred-pro
be machinery):

- Every probe attempt
 re-triggers the
 deferred workqueue (`
driver_deferred
_probe_trigger`),
 so the panel retries
 on every successful probe
 elsewhere
 — but **if
 the rpm_requests chain
 never completes, there
 is nothing that ever
 produces
 its supply**.

- `CONFIG
_DRIVER_DEFERRED
_PROBE_TIMEOUT`:
 `default 0
 if
 !MODULES,
 default 10
 if MODULES`
 (drivers/base/K
config). After `
deferred_probe_init
call`, if the
 timeout is set,
 `deferred_probe
_timeout
_work_func()` calls
 `fw_devlink
_drivers_done()`
 and `driver_def
erred
_probe_check_state()`
 starts returning `-ET
IMEDOUT`
 for still-defer
red
 devices; before that
 it returns
 `-EPROBE
_DEFER` forever
. Boot
 param: `defer
red_probe
_timeout=N`. The
 work also **prints
 every still-p
ending deferred device with
 reason
** (`"defer
red probe pending
: ..."`),
 which is
 exactly the dmes
g signature
 of a dead RPM
 edge.
-
 `
deferred_probe_timeout
=`
 param and `driver
_def
erred_probe_check
_state()` semantics:
 https://github
.com/torval
ds/linux/blob/master
/drivers/base/dd.c


### Known cases
 where
 consumers defer forever


-
 postmarketOS sdm
660 platform
 page (display bring
-up context): https
://wiki
.postmarketos.org
/wiki/Qualcomm
_Snapdragon_
660/
630/
636_(
SDM66
0/SDM
630/
SDM63
6)
-
 Practical writeup of
 exactly
 this failure mode (
panel
/display supplies, "
make sure fixed-reg
ulator is enabled,
 mysterious deferred
 probes"): https://
knuxify.github
.io/blog/2
023/
04/tab3
-display.html
-
 Classic reference on complex
 defer chains (every
 probe re-triggers
 all
 deferred devices): Andr
zej Hajda,
 ELC 2
0
17 PDF,
 https://events1
9.linuxfoundation
.org/wp-content/uploads
/201
7/12
/Deferred-Problem
-Issues-With
-Complex-Dependencies
-Between-Devices
-in-Linux-K
ernel.pdf
-
 msm
8916
-mainline has hit
 analogous rpm/smd
 ordering
 issues repeatedly (their
 panel generator
 docs discuss regulator gating
 of panels): https
://github
.com/msm8
916-main
line/linux-mdss
-dsi-panel-driver
-generator

---


## (b
) Does qcom
,rpm-pm
660-reg
ulators need RPM running
? What if RPM
 firmware never loads
?

**Verified
 facts:**


1. SDM6
60 uses
 **RPM over
 g
link-SMD**,
 not RPMh.
 `qcom,
pm
660-r
pmh-regulators
` does exist in
 `q
com-rpmh
-regulator.c`
 (for PMIC
-on-RPMh
 platforms
; probe depends on
 `cmd_db
_read_addr()` →
 `-ENODEV`
 if cmd-db missing
: https://github
.com/torval
ds/linux/blob/master
/drivers/regulator/q
com-rpmh
-regulator.c line
 ~531
), but **no
 mainline SDM6
6
0 DTS uses
 it**. sdm6
3
0.dtsi
 and sdm66
0-x
iaomi-lav
ender.dts use
 `qcom,r
pm-pm6
60(l)-
regulators`
 under rpm_requests.
 (Verified
 by grepping both
 files.)
2
. The kernel never
 boots RPM on these
 SoCs. The
 rpm
-proc patch states
 explicitly: *"The
 RPM
 firmware is usually already
 loaded and started by
 earlier components in the
 boot chain and is
 not meant to be
 ever restarted."*
 (https://lk
ml.indiana.edu
/230
6.0/
0391
3.html ; source
: rpm-proc
.c has
 no rproc_start
).

3. Therefore
 `/lib/firmware
`
 content is irrelevant to
 RPM on SDM
660.
 A minimal rescue init
ramfs without
 it does not affect
 RPM regulators **as
 long as RPM was
 already started by the
 boot chain**. Evidence
 this works in practice
:
 postmarketOS sdm
660 kernels
 boot initramfs
 shells with RPM regulators
/r
pmcc/rp
mpd active (
platform
 page + sdm6
60-main
line tree: https
://github
.com/sdm6
60-mainline
/linux ; Linaro
's
 mainline-boot guide
 for Qualcomm uses exactly
 this minimal
-initramfs flow
: https://www
.linaro.org
/blog/let-s
-boot-the-mainline
-linux-kernel-on
-qualcomm-dev
ices).
4
. Qualcomm boot-chain
 documentation: XBL
 "
initializes the hardware
, firmware images,
 ... PMIC,
 and DDR" (
https://docs.qual
comm.com/doc/
80-8
0021
-4/topic/boot
loader.html ; https
://docs.qual
comm.com/doc/
80-
7002
9-3/topic
/boot-flow-and
-architecture-overview
.html). Third-party
:
 XBL loads Trust
Zone + RPM/A
OP firmware
 before the kernel (
https://
squadri.me
/posts/Android-
Boot-Sequence-
1). Lineage
OS chain-of
-trust describes S
BL/XBL bringing
 up "core processes
 ...
 such as TrustZone
"
 (https://line
ageos.org/engine
ering/Qualcomm
-Firmware).


**Inference (
high confidence):** On
 the
 R11s
, RPM starts between
 XBL and A
BL as part of
 the stock
 boot chain; nothing
 the rescue kernel does
 (or
 omits) can
 start
 or restart it.
 So
 "PM66
0 RPM
 regulators never register in
 the rescue initram
fs
" can only mean
:
 (i) the
 To
C parse failed (
rpm
-msg-ram not
 mapped/populated →
 `qcom,g
link-r
pm` probe error
 at boot, very
 early in dmes
g),
 (ii) the
 IRQ/mailbox never
 signaled
 the channel open (
RPM dead
 or handoff state
 lost), or (
iii
) a missing/b
roken config (CONFIG
_QCOM_G
LINK_RPM /
 mailbox driver) —
 not a firmware-loading
 problem.

**
Direct answer to the
 key question:** On
 a
 minimal initramfs
 boot where the RPM
 edge
 never comes up,
 **
no, the pm
660
 RPM regulators will never
 register**, and users
pace has no lever
 to fix it on
 SDM660
 (
nothing to `request
_firmware`,
 no remoteproc
 to
 boot). Diagnostics
: check
 dmesg for
 `
qcom,glink
-r
pm` ToC
 errors
, `cat /
sys/kernel
/debug/devices_defer
red`, watch for
 the
 `deferred probe
 pending
:` dump after the
 timeout, and
 check whether `rpm
_requests` appears
 in `/sys/bus
/r
pmsg/devices/
`.

**
Upstream-correct
 fallback options (verified
):**

1.
 **`regulator
-fixed` for known
-on rails** —
 this
 is what mainline
 SDM
660 board
 DTSes already
 do for non-R
PM supplies (lav
ender.dts has
 a fixed regulator node
; verified). Suitable
 for a minimal debug
 DT: describe only
 the rails you need
 (e.g.,
 a model of the
 panel supply
) as fixed,
 matching the voltages
 firmware
 left enabled.

2.
 **Do NOT substitute
 `qcom,
pm660
-regulators` (
SPMI, CONFIG
_REGULATOR_QCOM
_SPMI)**
 even though it exists
 upstream with
 full pm66
0/pm
660l
 tables (`drivers/reg
ulator/q
com_spmi
-regulator.c`,
 compatibles verified at lines
 2
475-
2476
; pm66
0.d
tsi has a
 `pm6
60_spm
i_regulators`
 node). On SDM
66
0 the actual rail
 ownership lives with the
 RPM firmware (
SMD RPM resources
 `LDOA
/
SMPS`, verified
 in qcom_s
md-regulator.c
 tables). Bypass
ing RPM
 via SPMI
 while RPM firmware holds
 active votes risks inconsistent
 hardware state and is
 not
 how any upstream SDM
660
 DTS is built
. Mainline precedent
 on this exact family
: msm
8916
/ms
m899
8/lavender
 all use
 the RPM-path regulators
.
3
. **The correct
 fix
 for "panel def
ers forever"
 is to make the
 RPM edge
 come up** —
 verify CONFIG_QCOM
_A
PCS_IPC (
mailbox), CONFIG_Q
COM_GLINK_R
PM (or =
m with the modules
 actually present in the
 initram
fs), CONFIG_Q
COM_SMD_R
PM, CONFIG_REG
ULATOR_QCOM_S
MD_RPM are
 all built-in or
 available, and that
 the DT rpm node
 matches `sdm
630
.dtsi`
 (msg-ram
 phandle, irq
 168
, apcs_g
lb). If those
 are right and the
 channel still
 never opens, that
 is a firmware/h
andoff problem outside
 the kernel's control
 —
 fall back to option
 1 and keep
 the display
 off the critical path
,
 consistent with the project
's USB-first gating
.

### Facts
 vs inference — summary


- **Facts
 (read
 from torvalds
/linux master
 + LKML
 archives):**
 entire probe chain above
 (rpm-proc
.c
, qcom_g
link_r
pm.c ToC
 gate, qcom
_glink_native.c
 remote-open, sm
d-rpm.c
 of_platform_populate
, qcom_s
md-regulator.c
 parent-drvdata
 requirement
, regulator-core -
ENODEV→
-EPROBE
_DEFER, dd
.c timeout machinery,
 K
config defaults, sdm
630/l
avender/pm6
60 D
TS topology, S
PMI vs RPM
h driver
 compatibles).
-
 **
Facts (vendor
/community docs):** X
BL
 initializes firmware images incl
. PMIC before
 kernel; rpm-pro
c patch statement that
 RPM is started
 by boot chain;
 postmarketOS sdm
660 boots
 with RPM regulators in
 initramfs.

- **In
ference:** R1
1s
-specific RPM start point
 (between XBL
 and
 ABL) is
 inferred from generic Qualcomm
 boot docs +
 sdm660
 platform behavior; the
 claim
 that "SPMI
 bypass
 risks inconsistent state"
 is engineering
 inference (RPM
 firmware holds
 its own votes;
 no public upstream incident
 cited).