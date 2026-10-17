# R11s 17011 Mainline DTS Design Baseline

**Status:** Design review only. This is not a DTS file and does not authorize
building, packaging, booting, flashing, or otherwise operating the device.

**Date:** 2026-07-31

## Scope

This document records the minimum board facts required to eventually add an
OPPO R11s (17011) board DTS to mainline Linux. It separates live-device facts
from upstream binding references and from unresolved board parameters.

Evidence priority:

1. R11s official kernel/DTS or official boot/DTB/DTBO
2. R11s live read-only device data
3. Same-SoC and same-PMIC boards
4. SDM660 Xiaomi lavender upstream DTS
5. Hypothesis

Only levels 1 and 2 are R11s facts. Lavender is a binding and structure
reference only.

## Confirmed Board Facts

| Area | Confirmed fact | Evidence |
|---|---|---|
| Identity | OPPO R11s, SDM660, board-id 17011, PM660 and PM660L | `R11S_17011_DTS_LIVE_DT_MATRIX.md`, `device_tree_live/root_compatible.txt` |
| Primary USB | DWC3 child is at `0xa800000`, observed UDC name is `a800000.dwc3`, and it was `configured` | `device_tree_live/ssusb_a800000.txt` |
| USB mode | Primary DWC3 is high-speed only; downstream SuperSpeed PHY is disabled | `R11S_17011_DTS_LIVE_DT_MATRIX.md` |
| Primary PHY | QUSB2 PHY is at `0xc012000` | `device_tree_live/usb_pmic_reserved.txt` |
| Secondary USB | `hsusb@c200000` is disabled | `device_tree_live/hsusb_c200000.txt` |
| eMMC | Controller is at `0xc0c4000`, is enabled, and bootargs select `c0c4000.sdhci` | `device_tree_live/reserved_uart_emmc_boardid.txt` |
| PMIC | PM660 and PM660L SPMI topology is present | `device_tree_live/usb_pmic_reserved.txt` |
| UART | Only `uart@c1af000` is enabled in the live DT; console routing and physical accessibility are not proven | `device_tree_live/reserved_uart_emmc_boardid.txt` |
| ramoops | No ramoops node or pstore data was observed | `R11S_17011_DTS_LIVE_DT_MATRIX.md` |

## Upstream Reference Structure

The future board DTS may use these upstream files as binding references:

- `linux/arch/arm64/boot/dts/qcom/sdm660.dtsi`
- `linux/arch/arm64/boot/dts/qcom/sdm630.dtsi`
- `linux/arch/arm64/boot/dts/qcom/pm660.dtsi`
- `linux/arch/arm64/boot/dts/qcom/pm660l.dtsi`
- `linux/arch/arm64/boot/dts/qcom/sdm660-xiaomi-lavender.dts`

Candidate future board file name: `sdm660-oppo-r11s.dts`.

This candidate name is a design placeholder. No DTS file is created by this
document.

## Future Minimal Node Intent

Once all gates below pass, the first board DTS should be limited to:

- SDM660 and PM660/PM660L include chain.
- R11s model and compatible values from live 17011 evidence.
- Primary DWC3 in USB2 high-speed peripheral mode, using the upstream DWC3
  wrapper/core split and the upstream QUSB2 PHY binding.
- Explicitly disabled secondary HSUSB and SuperSpeed PHY path.
- eMMC controller identity at `c0c4000` only.
- R11s fixed and dynamic reserved-memory constraints.

The first DTS must not include display, touch, audio, Wi-Fi, Bluetooth, modem,
DSP remoteproc, camera, fingerprint, VOOC, SD card, or UART console setup.

## Reserved Memory Constraints

These ranges are live 17011 facts and must not be used as normal RAM:

| Node | Base | Size | Required property |
|---|---:|---:|---|
| wlan_msa_guard | `0x85600000` | `0x00100000` | no-map |
| wlan_msa_mem | `0x85700000` | `0x00100000` | no-map |
| removed_regions | `0x85800000` | `0x05300000` | no-map |
| modem_fw_region | `0x8ac00000` | `0x07e00000` | no-map |
| adsp_fw_region | `0x92a00000` | `0x02000000` | no-map |
| pil_mba_region | `0x94a00000` | `0x00200000` | no-map |
| cdsp_fw_region | `0x94c00000` | `0x00600000` | no-map |
| splash_region | `0x9d400000` | `0x02300000` | preserve as layout constraint |

Live dynamic-pool constraints:

| Node | Size | Alignment | Alloc range | Extra |
|---|---:|---:|---|---|
| venus_fw_region | `0x00800000` | `0x00400000` | `0x80000000/0x20000000` | reusable |
| adsp_region | `0x00800000` | `0x00400000` | full 32-bit range | reusable |
| qseecom_region | `0x01400000` | `0x00400000` | full 32-bit range | reusable |
| secure_region | `0x05c00000` | `0x00400000` | full 32-bit range | reusable |
| linux,cma | `0x02c00000` | `0x00400000` | full 32-bit range | reusable, cma-default |

These facts do not establish that every Android DSP/QSEE pool must be consumed
by a mainline driver. They are memory-layout constraints pending a full memory
and bootloader-reservation review.

## Explicitly Prohibited Parameters

The following must not be copied from vendor DTS files or lavender into an
R11s DTS:

- Vendor `qcom,*` DWC3 DBM, IPA, BAM, bus-vote, and PHY-init properties.
- Lavender USB ID GPIO, extcon node, VBUS regulator, or charger setup.
- Lavender QUSB2 regulator labels, voltages, loads, or rail choices.
- Lavender eMMC rails, pinctrl, HS200, HS400, CQE, or enhanced-strobe flags.
- Any MTP GPIO, regulator, charger, Type-C, or storage-timing values.
- UART aliases, pinctrl, stdout-path, earlycon, or console configuration.
- A ramoops address.
- `removed-dma-pool` as an upstream compatible string.
- Any property sourced solely from the board-id 17021 third-party DTS.

## Gates Before Creating and Compiling an R11s DTS

1. Official C.19 OZIP payloads must be decrypted/extracted read-only and each
   relevant object independently hashed and audited.
2. A matching official boot/recovery/DTBO-if-present and partition/recovery
   record must be complete and verified.
3. Fastboot unlock state and `fastboot boot` capability must be documented by
   read-only observation.
4. R11s eMMC rails, pinctrl, and timing must be evidenced from 17011 material.
5. USB role detection, VBUS, and QUSB2 rail mapping must be reviewed against
   the relevant upstream bindings.
6. A full RAM and bootloader-reservation review must select a non-overlapping
   ramoops range before ramoops is introduced.
7. Each proposed node/property must pass an independent upstream-binding review.
8. A source backup and a static DTS validation plan must be recorded before any
   R11s DTS source change.

## Ubuntu User-Space Direction

The eventual first user-space target is USB-first:

`DWC3/QUSB2 probe -> UDC -> CDC ACM -> ECM or NCM -> Ubuntu shell`

USB gadget operation cannot diagnose faults before DWC3 probe. Therefore a
later design must independently provide early failure evidence after a safe
ramoops range is selected, or another board-evidenced visibility path.

No Ubuntu rootfs, initramfs, boot image, or device-facing command is produced
by this document.

## Source Index

- `CLAUDE.md`
- `PLAN.md`
- `STATUS.md`
- `recon/P2_R11S_MINIMAL_DTS_EVIDENCE_MATRIX.md`
- `recon/R11S_17011_DTS_LIVE_DT_MATRIX.md`
- `recon/p0_adb_readonly_20260730_033057/device_tree_live/`
- `recon/p2_adb_live_dt_complete_20260730_105747/raw_properties/`

---

## Updated 2026-08-01

Status note: the sections above remain the design baseline and all gates are
unchanged. The additions below are live 17011 observations made after the
original baseline. No DTS file is created, modified, or compiled by this
document.

### QUSB2 rails confirmed via live phandles

The QUSB2 PHY at `0xc012000` does not name its regulators directly in the live
DT. The rail identities are confirmed by following the phandle from the live
`0xc012000` node into the PMIC regulator nodes, which resolves to:

| Regulator handle | Confirmed rail |
|---|---|
| `regulator@3` (L1) | QUSB2 HV supply |
| `regulator@14` (L10) | QUSB2 1.8 V supply |
| `regulator@9` (L7) | QUSB2 1.9 V supply |

These are 17011 live phandle facts, not lavender choices. The upstream
`qcom,qusb2-phy` binding's supply names (`vdd-supply`, `vdda-pll-supply`,
`vdda-phy-dpdm-supply`) must still be matched to L1/L10/L7 in an independent
upstream-binding review before use (this remains part of gate 5).

### DWC3 extcon -> SMB2 confirmed

The live DT confirms the primary DWC3 (`0xa800000`) role detection is wired
through an extcon reference to the SMB2 charger driver node (not an ID GPIO
GPIO-based setup and not the lavender extcon node). Role detection therefore
routes through `pmi8998`/SMB2 VBUS and Type-C/ID detection.

Implication recorded for the first R11s DTS: the DWC3 extcon link must be
reexpressed against the upstream extcon bindings; it must not copy lavender's
extcon node or ID GPIO. This remains a USB-role-detection design item under
gate 5 and the "Explicitly Prohibited Parameters" section.

### Appended-DTB ABL mechanism confirmed

The R11s boot flow appends the DTB to the boot image and the Qualcomm ABL
(appended-DTB mechanism) consumes it. This means:

- The R11s boot.img carries its DTB appended at end-of-image rather than in a
  separate DTBO partition (no DTBO was evidenced in the live device).
- A mainline-flavored boot image for this device must preserve this appended-DTB
  contract so ABL can locate and pass the DTB to the kernel.
- This is a bootloader-visible packing constraint, not a DTS node change, and it
  feeds the boot-image packaging work item below.

### boot.img packaging params

Boot image packaging parameters evidenced/confirmed for the R11s 17011:

| Parameter | Value |
|---|---|
| Header format | Android boot image (ABL appended-DTB variant) |
| DTB placement | Appended to end of boot image (no separate DTBO) |
| DTB alignment | Aligned to the boot-image page size; verify against the live boot image |
| Kernel offset | Verify against the live boot image |
| Ramdisk offset | Verify against the live boot image |
| Second / tags offset | Verify against the live boot image |
| Board name | 17011 (board-id) |
| Page size / header size | Verify against the live boot image |

These packaging params are recorded only as design constraints. No boot image
is generated or tested by this document, and producing any testable image still
requires the gates below to pass, including the official firmware and
`fastboot boot` capability gates (gates 1-3).

### Gate status (unchanged)

All gates listed in "Gates Before Creating and Compiling an R11s DTS" remain in
force and unchanged by this update. The 2026-08-01 additions reduce unknowns in
gates 4, 5, and the boot-packaging path, but do not lift any gate.
