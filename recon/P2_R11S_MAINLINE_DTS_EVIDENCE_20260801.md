# R11s Mainline DTS Evidence Consolidation (2026-08-01)

Status: evidence only. No DTS/rootfs/image modified; no device operated.
Source: workflow wf-dts-usb-evidence (8 agents) + wf-dts-board-evidence (6 agents),
each mapping live 17011 DT facts to upstream Linux 7.2-rc5 bindings.

## USB subsystem (verified)

The upstream SDM660 wrapper `usb3: usb@a8f8800` in `sdm630.dtsi` is confirmed
consistent with live silicon:

- Upstream IRQ cells (pwr_event=180, qusb2_phy=347, ss_phy_irq=243, hs_phy_irq=133)
  match the live vendor DT (180/347/243; hs_phy_irq absent live).
- Live wrapper `ssusb@a800000` compatible `qcom,dwc-usb3-msm` is vendor-only and
  must NOT be copied. Upstream `qcom,sdm660-dwc3`,`qcom,dwc3` is the legal form.
- Live extcon 0x181 -> PM660 qpnp-smb2 (vendor charger, no upstream extcon
  provider); vbus 0x84 -> smb2-vbus; gdsc 0x17f -> gdsc@10f004; dbm 0x180 ->
  dbm@a8f8000 (no upstream driver). None of these enter the upstream DTS.
- Board DTS only needs the lavender-style overrides:
  - `&usb3 { status = "okay"; qcom,select-utmi-as-pipe-clk; }`
  - `&usb3_dwc3 { maximum-speed = "high-speed"; phys = <&qusb2phy0>;
    phy-names = "usb2-phy"; dr_mode = "peripheral"; }`
  - `&qusb2phy0 { status = "okay"; ... }` (supplies below)
- Deferred to fastboot boot test: extcon role wiring (peripheral mode is
  deterministic without it), vbus supply (no upstream equivalent), and PHY rail
  supply phandle mapping (live vendor vdda18/vdda33/vdd -> upstream
  vdd/vdda-pll/vdda-phy-dpdm on R11s PM660 regulators).

## PMIC/regulator rails (from wf-dts-pmic-evidence, consolidated)

Live QUSB2 rail phandles resolve to (P2 matrix already recorded this):
- vdd      -> PM660L L1 (0.925 V), upstream regulator label `vreg_l1b_0p925`
- vdda-pll -> PM660 L10 (1.8 V), upstream label `vreg_l10a_1p8`
- vdda-dpdm-> PM660L L7 (3.125 V), upstream label `vreg_l7b_3p125`
These labels/voltages match the mainline lavender DTS and are now directly
verified against R11s live phandles (not just lavender reference).
The sdm660-oppo-r11s.dts defines these three regulators under `&rpm_requests`
using `qcom,rpm-pm660l-regulators` and `qcom,rpm-pm660-regulators` compatible
strings (same as lavender). DTB built successfully.

## eMMC (corrected)

- Live DT only evidences controller identity: compatible `qcom,sdhci-msm-v5`,
  status ok, reg two ranges (0xc0c4000/0x1000 + 0xc0c5000/0x1000).
- Claims of bus-width=8 / nonremovable / HS400 originate from the third-party
  17011 downstream tree, NOT live evidence.
- Upstream sdm630.dtsi sdhc_1 already carries `bus-width = <8>` and
  `non-removable`; the R11s board DTS must NOT re-add them.
- Board override `&sdhc_1 { status = "okay"; }` is correct and sufficient for
  the first DTS. HS400/rails/pinctrl remain deferred.

## Identity (corrected)

- Mainline board DTS uses `model = "OPPO R11s"` and
  `compatible = "oppo,r11s", "qcom,sdm660"`.
- `oppo,r11s` is NOT yet in `qcom.yaml` sdm660 board enum -> dtbs_check fails.
  Companion patch (submission-time) required.
- `qcom,msm-id` and `qcom,board-id` are deprecated/forbidden for sdm660 in this
  tree's schema. They must NOT enter the board DTS. Live board-id 17011
  (0x4273) and msm-id 317 are confirmed evidence, and if the fastboot boot test
  shows ABL needs them, inject them only in the boot-image packaging step
  (post-compile DTB patch), never in upstream source.

## Boot image layout (confirmed)

Official C.19 boot.img and boot-debug.img are BOTH standard Android header v1:
- page_size@0x24 = 0x1000, header_version@0x28 = 1, cmdline@0x40,
  header_size = 0x670, kernel at file offset 0x1000.
- Kernel field carries appended FDT(s) which ABL extracts and passes via x0;
  mainline needs no appended-DTB patch.
- tools/mkbootimg_v1.py builds this layout (verified against official header
  fields). Packaging: cat Image.gz <dtb> > kernel.gz-dtb, then mkbootimg_v1.

## Files
- /home/<user>/claude/r11/linux/arch/arm64/boot/dts/qcom/sdm660-oppo-r11s.dts
- /home/<user>/claude/r11/tools/mkbootimg_v1.py
- /home/<user>/claude/r11/out/wf_bootimg_verify.md (pending main-path build)
- /home/<user>/claude/r11/out/test_flash_progress.md
