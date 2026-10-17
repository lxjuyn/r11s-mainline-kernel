# P2 R11s minimum DTS evidence matrix

Date: 2026-07-30

This is a host-only evidence matrix. It does not create an R11s DTS or a bootable artifact.

## Exact live 17011 anchors

- Identity: OPPO R11s, SDM660, board-id 17011, PM660 + PM660L.
- eMMC controller: `sdhci@c0c4000`; bootargs select `c0c4000.sdhci`.
- Gadget controller: `ssusb@a800000` with child `dwc3@a800000`; maximum speed is high-speed and the UDC was observed configured.
- Primary QUSB2 PHY: `qusb@c012000`.
- Secondary HSUSB: `hsusb@c200000`, disabled.
- SPMI controller and PM660/PM660L presence are live-evidenced.
- Fixed and dynamic reserved-memory node names/base anchors are live-evidenced. A later selected-property capture also includes fixed-region `reg` and `no-map`, plus dynamic-pool `size`, `alloc-ranges`, and `alignment`; a safe new ramoops location is still not selected.

Sources: `R11S_17011_DTS_LIVE_DT_MATRIX.md`, `P0_ADB_EVIDENCE_REPORT.md`, and raw files under `recon/p0_adb_readonly_20260730_033057/device_tree_live/`.

## Reference-only sources

- User DTS `r11s..dts` is board-id 17021, not the live 17011 ID. User reports it works downstream, but this project has not built or boot-tested it.
- Upstream `sdm660-xiaomi-lavender.dts` supplies binding labels and structure only. Its eMMC rails, USB extcon GPIO, USB PHY rails, speed choice, and ramoops address are not R11s facts.

## Completed live 17011 property capture

`recon/p2_adb_live_dt_complete_20260730_105747/` contains a read-only selected-property capture, manifest, and SHA256SUMS. Direct `/sys/firmware/fdt` access was denied by Android permissions, so its saved `live_17011.fdt` is error text, not a DTB.

Resolved live graph: SSUSB extcon `0x181` targets the PM660 SMB2 charger; VBUS `0x84` targets `smb2-vbus`; USB3 GDSC `0x17f` targets enabled `gdsc_usb30`; PHY cells target QUSB2 `qusb@c012000` and `usb_nop_phy`. QUSB2 rail phandles resolve to RPM regulator nodes L1, L10, and L7. This is 17011 topology evidence only; vendor binding properties must not be copied to upstream DTS.

All seven fixed removed-dma-pool regions now have live `reg` and `no-map` captures. Dynamic pools have live size, alloc-ranges, alignment, and reusable captures. Safe ramoops placement remains unselected pending a separate full-RAM/bootloader-reservation review.

## Future minimum DTS policy

May be represented only after binding-level implementation review: SDM660 SoC include, identity, evidenced eMMC-controller label/address, evidenced DWC3/QUSB2 address chain, and memory constraints.

Do not add yet: eMMC rails/pinctrl/HS400 tuning; USB extcon or VBUS targets; charger/Type-C GPIOs; regulator voltage/load values; UART console settings; ramoops address; display, wireless, audio, modem, camera, or any device-specific GPIO.

## Outstanding evidence gates

- Decode 17011 live phandle targets for USB extcon, VBUS, and PHY supplies.
- Obtain full memory `reg`/`no-map` evidence before planning ramoops.
- Verify eMMC rails/pinctrl/timing and USB role detection from 17011-compatible evidence.
- Do not compile or package R11s DTS until those gates are independently reviewed.
