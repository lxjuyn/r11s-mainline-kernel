# SDM660 mainline panel/regulator ecosystem research (R11s display bring-up, v13 task (c))

Agent: web research subagent (workflow v13, resumed after crash) — 2026-08-31
Method: web (GitHub API, kernel.org mirrors) + direct source reads from (a) local tarball of an ASUS
ZenFone Max Pro M1 stock CLE OEM tree, (b) upstream mainline DTS for SDM660 boards fetched from
torvalds/linux master, (c) the R11s OEM decompiled DTB text and OPPO SDM660 source drop already
present in this repo. Facts vs inference are separated per section. URLs are inline.

Note on the third web question: "postmarketOS / mainline efforts for SDM660 devices with Samsung AMOLED
panels and PM660L oledb/lab/ibb regulators" — the honest web answer is that **no mainline device with an
AMOLED panel currently enables its lab/ibb/boost supplies through a real driver**; all of them model the
AMOLED boost as `regulator-fixed` (see D2, and the known upstream TODO in panel-jdi-fhd-r63452.c).
Details and evidence below.

---

## A. Mainline SDM660 boards and how they wire panel supplies (facts, read from upstream DTS)

Upstream DTS files read (https://github.com/torvalds/linux/tree/master/arch/arm64/boot/dts/qcom/):

| Board (DTS) | Panel | Panel compatible (upstream driver) | Panel supplies | AMOLED boost handling |
|---|---|---|---|---|
| Xiaomi Mi A2 jasmine (`sdm660-xiaomi-jasmine.dts`) | Tianma TL060FVXS16-00 | `"tianma,tl060fvxs16-00", "novatek,nt36672a"` | `vddio-supply = <&vreg_l11a_1p8>` (PM660L RPM L11, 1.8V); `vddpos-supply`/`vddneg-supply = <&lcdb_fixed>` | **`lcdb_fixed`: `regulator-fixed`, 5.5V, `regulator-always-on` + `regulator-boot-on`** (comment in tree: "This is here until we have a driver for QPNP LCDB regulator") |
| Xiaomi Redmi Note 7 lavender (`sdm660-xiaomi-lavender.dts` + `sdm660-xiaomi-lavender-common.dtsi`) | (panel node has no supplies at all in common dtsi) | — | — | panel node intentionally minimal; display WIP (panel page on pmos wiki) |
| BlackBerry Athena/Luna (`bbry.dtsi` common; 2025, Paul Sajna) | nt36672a-family | `panel: panel@0` | `vddio-supply = <&vreg_l11a_1p8>`; `vddneg-supply`/`vddpos-supply = <&lcdb_fixed>` | identical **`lcdb_fixed` 5.5V fixed** workaround; same fixed rail also feeds the touch controller (`vdd-supply`) |
| Xiaomi Mi Note 3 jason (`sdm660-xiaomi-jason.dts`) | JDI FHD R63452 | `"jdi,fhd-r63452"` | `power-supply = <&vreg_l11a_1p8>` only | driver/bindings do not support the extra supplies; DTS comment: "when it does, add these: vddpos-supply/vddneg-supply = <&lcdb_fixed>" |

Key verified facts:

1. **No upstream SDM660 board wires lab/ibb/oledb to a real regulator driver.** Every AMOLED-equipped
   SDM660 board in mainline uses the `lcdb_fixed` regulator-fixed trick for the positive/negative boost.
   (Read directly from the DTS files above.)
2. **The PM660L LCDB peripheral is at SPMI offset 0xec00** and the oledb at **0xe000**, labibb lab/ibb
   at 0xde00/0xdc00 — verified in three independent sources: OEM R11s DTB (see B), ASUS stock
   `arch/arm/boot/dts/qcom/msm-pm660l.dtsi` (see C), and the downstream drivers
   `qpnp-lcdb-regulator.c`/`qpnp-oledb-regulator.c`/`qpnp-labibb-regulator.c` in that tree.
3. **Which PM660L LCDB variant each phone actually has is device-specific** (PM660L vs PM660A variants);
   OEM R11s DTB contains both an LCDB node (status "disabled") and an OLEDB node (status "okay").
   Do not assume LCDB presence from another device.
4. RPM-supplied rails used by panels are the same everywhere: `vreg_l11a_1p8` (1.8V vddio) and
   `vreg_l1a_1p225`/`vreg_l1b_0p925` for the DSI controller/PHY (verified in all four boards).

## B. R11s OEM panel power topology — verified from OEM evidence in this repo (facts)

Sources: `/home/<user>/claude/r11/r11s..dts` (official R11s DTB decompilation),
`/home/<user>/claude/r11/android_kernel_oppo_sdm660_source_d9391f88aa90/arch/arm64/boot/dts/vendor/qcom/`
(OPPO source drop), `/home/<user>/claude/r11/recon/R11S_PANEL_FORENSICS_20260829.md`.

1. Panel identity: Samsung SOFEG01_S, 1080x2160, DSI cmd-mode AMOLED (already established 2026-08-29).
   Second variant in the OEM table: `ams596w401` 1080x2280 cmd (panel-version "SOFEG01_S-QC01") —
   same family, different timings/status-value (0x9c vs 0x9e). Both use the same supply table.
2. **OEM supply wiring (R11s DTB, lines 16617-16619 on `qcom,mdss_dsi_ctrl0@c994000`):**
   - `oledb-supply = <0x28f>` → PM660L `qpnp-oledb@e000` (compatible `qcom,qpnp-oledb-regulator`,
     5.0-8.1V, `qcom,swire-control`, `qcom,ext-pin-control`, **status "okay"**) — the AMOLED boost.
   - `lab-supply = <0x290>` → `qpnp-labibb-regulator / qcom,lab@de00` ("lab_reg", 4.6-6.0625V).
   - `ibb-supply = <0x291>` → `qpnp-labibb-regulator / qcom,ibb@dc00` ("ibb_reg", 1.4-6.3V range).
   - The `qpnp-lcdb@ec00` node exists but is **status "disabled"** on R11s — R11s uses OLEDB+LABIBB,
     **not** LCDB. (This differs from jasmine/bbry hardware.)
3. Panel-node supply table (DTB 16818 and source-drop `oppo-sdm660-common.dtsi`
   `oppo_dsi_panel_pwr_supply_amoled`): only two entries —
   `wqhd-vddio` = 1.8V (32000 uA load) and `vdda-3p3` = 3.0V (13200 uA load).
   Resolved phandles: `wqhd-vddio = pm660_l14` (rpm-smd ldoa14, 1.7-1.9V),
   `vdda-3p3 = pm660l_l6` (rpm-smd ldob6, 1.7-3.3V).
4. The boost rails (oledb/lab/ibb) are attached to the **DSI controller node**, not the panel node,
   in downstream; they are enabled via dsi_display before panel init, and the OEM init command sequence
   includes sleep-out (0x11) with a 20 ms (0x14) delay before display-on (0x29).
5. Reset: TLMM GPIO 53 (`qcom,platform-reset-gpio`), sequence 1-5ms / 0-2ms / 1-12ms. Backlight is DCS
   (11-bit, max 1023). ESD check reads 0x0A expecting 0x9e (SOFEG01_S).

## C. Downstream reference: ASUS ZenFone Max Pro M1 (X00TD, SDM636/PM660L) stock tree (facts)

Source: https://github.com/amitwh/android_kernel_asus_X00TD branch `17.2017.2008.432` (fetched as tarball
2026-08-31 to /tmp/asus_x00td). Relevant files (all under arch/arm/boot/dts/qcom/):

- `msm-pm660l.dtsi`:
  - `pm660a_oledb: qpnp-oledb@e000` — compatible `qcom,qpnp-oledb-regulator`,
    regulator-name "regulator-oledb", 5.0-8.1V, `qcom,swire-control; qcom,ext-pin-control;`
    **status = "disabled"** in the CLE base tree.
  - `pm660a_labibb: qpnp-labibb-regulator` — `qcom,swire-control;` with child nodes
    `ibb@dc00` (1.4V-…, init-amoled-voltage 4.0V, max-current-200mA limit) and `lab@de00`
    (min 4.6V, step 100mV, slew 5000, init 4.6V). Status overridden to **"okay"** with a Huaqin
    board comment ("Huaqin modify for ZQL1650 ... status = okay").
  - `pm660l_lcdb: qpnp-lcdb@ec00` present (ldo + ncp children, 4.0-6.0V).
- `sdm660-mdss.dtsi` (CLE MDSS): `lab-supply = <&lcdb_ldo_vreg>; ibb-supply = <&lcdb_ncp_vreg>;`
  and `vdda-3p3-supply = <&pm660l_l6>;` + `wqhd-vddio-supply = <&pm660_l11>;` on the DSI ctrl nodes.
- `sdm660-mdss-panels.dtsi`: `dsi_panel_pwr_supply_labibb_amoled` supply table:
  `wqhd-vddio` 1.8-1.95V/32000uA; `vdda-3p3` 3.0V (implied by later entry); `lab` 4.6-6.0V/100000uA;
  `ibb` 4.6-6.0V/100000uA with `qcom,supply-post-on-sleep = <10>` (10 ms settle after enable).
- CDP/QRD boards wire `oledb-supply = <&pm660a_oledb>` on the DSI ctrl (e.g. `sdm636-pm660a-cdp.dts`);
  `msm-pm660a.dtsi` and `sda660-pm660a-qrd-hdk.dts` override `&pm660a_oledb { status = "okay"; }`.

Facts to take away:
- On PM660L hardware the AMOLED boost is the **OLEDB peripheral (0xe000) driven via SWIRE (PBS)** —
  the same topology as R11s (matches B.2 exactly, down to compatible strings and offsets).
- CLE boards sometimes instead use **LCDB** ldo/ncp for lab/ibb roles — a hardware-option question;
  R11s DTB shows LCDB disabled and OLEDB okay, so R11s = OLEDB+LABIBB variant.
- `qcom,supply-post-on-sleep = <10>` documents the required post-enable settle delay for lab/ibb.

## D. Driver availability for R11s panel in upstream (Linux 7.2-rc5, verified from /home/<user>/claude/r11/linux)

1. **lab/ibb:** `drivers/regulator/qcom-labibb-regulator.c` exists but is **PMI8998-specific**:
   only compatible `qcom,pmi8998-lab-ibb` (+ pmi8950 fallback); hardcoded bases 0xde00/0xdc00; binding
   `qcom-labibb-regulator.yaml` has no pm660l variant. **No mainline driver for `qcom,qpnp-labibb-regulator`.**
   (Note: the PMI8998 lab/ibb bases happen to be identical offsets to PM660L's 0xde00/0xdc00, and register
   semantics are similar — but upstream never added pm660l support; the downstream driver also uses SPMI
   PBS/swire sequencing that plain register writes do not cover. Treat "reuse pmi8998 driver" as unverified.)
2. **oledb:** no upstream driver at all (`grep -r oledb drivers/regulator/` empty).
3. **lcdb:** no upstream driver (jason/bbry DTS comments confirm this is a known gap).
4. **panel driver for SOFEG01_S:** no upstream driver; closest relatives present in tree:
   `panel-samsung-s6e3ha2.c`, `panel-samsung-sofef00.c`, `panel-samsung-s6e3ha8.c` (none compatible),
   `panel-jdi-fhd-r63452.c` (compatible "jdi,fhd-r63452", takes a single `power-supply`; its TODO
   explicitly calls out the missing vddpos/vddneg supplies), `panel-novatek-nt36672a.c` (has full
   regulator_bulk support: names at `nt36672a_regulator_names[]`).
5. **Upstream panel driver regulator idioms:** either (a) regulator_bulk_get of named supplies with
   per-enable load settings (nt36672a), or (b) simple single-supply `devm_regulator_get` (r63452).
   A new SOFEG01_S driver would follow pattern (a) with supplies `vddio` (1.8V), `vdda` (3.0V) and
   either optional `vddpos`/`vddneg` or none if the fixed-rail workaround is used.

## E. -EPROBE_DEFER implications for v13 rescue DT (facts from web research + local code reads)

From recon/WEB_RESEARCH_V12_PANEL_RPM_DEFER_20260831.md (this session, verified against torvalds source):

1. `qcom,rpm-pm660(l)-regulators` under `&rpm_requests` registers only after the RPM glink channel
   opens; if it does not, every `-supply` phandle into it keeps consumers in -EPROBE_DEFER (converted
   from -ENODEV by regulator core), then -ETIMEDOUT after `deferred_probe_timeout` (default 10s with
   CONFIG_MODULES), printing "deferred probe pending:" lines.
2. The R11s v12 display attempt hit exactly this class of problem (panel supplies under RPM regulators).
3. Upstream-correct mitigations used by real SDM660 boards:
   - jasmine/bbry: **`lcdb_fixed` regulator-fixed with `regulator-always-on; regulator-boot-on;`** so
     the probe never depends on RPM for the boost rails; vddio still comes from RPM (defer-tolerant).
   - For a rescue initramfs DT that must not defer at all, the same trick applies to the vddio rail if
     needed (model it as fixed at the firmware-left voltage) — but note R11s vddio = pm660_l14 (1.8V),
     not l11a.

## F. Recommendations for v13 R11s display DT (inference — engineering judgment, flagged)

Ranked by safety/effort:

1. **Keep the display out of the USB-critical path** (project gate). Panel can stay deferred without
   harm as long as nothing else depends on it.
2. If v13 wants a non-deferring panel probe: mirror jasmine exactly —
   - `vddio-supply` → model the 1.8V rail. Two options: (a) keep the RPM phandle (`vreg_l14a_1p8`) and
     accept deferral until RPM edge is up; (b) a `regulator-fixed` 1.8V `regulator-boot-on` node
     (risk: does not actually re-enable the rail if firmware left it off — R11s firmware leaves splash
     rails on, so acceptable for rescue purposes).
   - boost rails: `regulator-fixed` nodes ("oledb_fixed"/"labibb_fixed") pinned to the firmware-set
     voltages (`regulator-always-on; regulator-boot-on;`), exactly like `lcdb_fixed` in jasmine/bbry.
     Firmware-set values from OEM DTB init fields: lab 4.6V init (`0x4630c0`), ibb amoled-init
     field present; oledb range 5.0-8.1V — the exact firmware-programmed oledb voltage is not visible
     in the DTB decompile (garbled cells), so measure or leave the fixed regulator without a strict
     voltage (min=max at a safe nominal like 5.5V is what jasmine does for LCDB; for OLEDB keep it
     as a "present but unmanaged" model).
   - Do **not** instantiate `qcom,qpnp-labibb-regulator`/`qpnp-oledb-regulator` nodes expecting a
     driver: no upstream driver exists and adding downstream SPMI control while RPM firmware owns the
     rails risks conflicting votes (same reasoning as the SPMI-vs-RPM regulator warning in the v12 report).
3. Long term: an upstream-quality SOFEG01_S panel driver would need either a PM660L LCDB/OLEDB/LABIBB
   regulator driver series (the 2024 kholk11 SMD/SPMI pm660 series covered LDO/SMPS but not the display
   boost peripherals — no public upstream OLEDB/LABIBB pm660l driver found) or continued fixed-regulator
   modelling. This is a web-research negative result, not a verified absence elsewhere.

## G. Source quality / confidence

- A, B, C, D, E.1-2: **verified from source files** (local tarballs/tree + repo files; GitHub URLs cited).
- E.3, F: **inference**, based on the verified facts and upstream-idiomatic precedent.
- Web-only claims that could NOT be verified this session (treated as leads, not facts):
  - kholk11 lore thread on pm660 SMD regulators status — lore.kernel.org is bot-walled from this host
    (known issue in this session; the SMD/SPMI pm660 tables ARE present in the local 7.2-rc5 tree,
    which is the load-bearing fact).
  - Any postmarketOS wiki statement was not re-fetched this session; the v12 report's pmOS links stand.
