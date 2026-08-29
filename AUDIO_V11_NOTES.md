# Audio chain v11 round — config audit & candidate image notes (2026-08-30, task #33)

Host-side only; **no device flashed**. Companion archive:
`backups/products/products_r11s_phase3_audio_v11_20260830_055225/` (bilingual README, full
.config, config diff, DTB, SHA256SUMS). Prior audit: `recon/AUDIO_DTB_SURGERY_CANDIDATE_20260830.md`.

## What changed this round

1. **Audio boot-chain fully built-in (=y)** in `build/r11s_phase2/.config` (O= build dir; the
   in-tree `.config` is gitignored, so the config itself is tracked only via the archive above
   and the backup `backups/source/config_r11s_phase2_pre_audio_v11_20260830_054510.bak`).
   Rationale: rescue ramdisk and phase-4a rootfs have no /lib/modules; =m drivers never load.
   Converted (m→y): `SND_SOC_SDM660_INT` (machine driver matching DTB sound node
   `qcom,sdm660-internal-sndcard`), `SND_SOC_TFA989X` (speaker amp, matches `nxp,tfa9890`),
   `SND_SOC_LPASS_CPU`, `SND_SOC_LPASS_PLATFORM`, `SND_SOC_LPASS_APQ8016`, `SND_SOC_APQ8016_SBC`,
   `PINCTRL_LPASS_LPI`, `PINCTRL_SDM660_LPASS_LPI`. QDSP6/APR/Q6V5_PAS/GLINK/AK4375/WCD codecs
   were already =y. `SND_SOC_QDSP6_USB`/`SND_SOC_QCOM_OFFLOAD_UTILS` left =m (USB-offload only,
   depends on the =m USB gadget chain, no DTB node).
2. **`CONFIG_SND_SOC_SDM660_OPPO_R11S` disabled (y→n).** The DTB sound node is
   `qcom,sdm660-internal-sndcard`, served by the existing `sound/soc/qcom/sdm660-internal.c`.
   The glue driver binds a downstream-style compatible and only looks for `maxim,max98927(L)`
   speakers — it does **not** know `nxp,tfa9890` (the actual board part), so it would defer
   forever even if enabled. Source kept in-tree for a possible downstream-DTB route; nothing
   deleted. Build verified: no dangling references, 0 warnings; the object is absent from both
   `modules.order` and `modules.builtin`.
3. **DTB = audio candidate** `out/v9_dtb/dtb_v9_audio_candidate.dtb` (sha256 `1f2ac674…`):
   two-line fix over authoritative `dtb_v9.dtb` — `#pinctrl-cells = <1>` on the lpass-lpi
   pinctrl, and adsp `firmware-name` → `qcom/sdm660/adsp.mdt` (matches firmware deployment
   path; this tree's mdt_loader has no platform-prefix logic).

## tfa9890 driver verdict

Present in-tree: `sound/soc/codecs/tfa989x.c`, of_match includes `nxp,tfa9890`; binding
`Documentation/devicetree/bindings/sound/nxp,tfa989x.yaml` enumerates it. No driver gap.

## Build / image

- `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=build/r11s_phase2 Image.gz modules` → EXIT=0, 0 warnings.
- Gate: decompressed Image 39,174,656 B ≤ 50,331,648 B.
- Image: `out/boot_r11s_phase3_audio_v11.img` (15,101,952 B, sha256
  `a07a5ef599ad8a1a07c63b88ef924d46051480f24084451acf27572f62a7c414`), packed with the v9 recipe
  (rescue ramdisk byte-identical to v9, cmdline without root=, os-version 0x12000139).
- Reconciled vs v9: header fields identical, ramdisk byte-identical, only kernel+DTB section
  differs (+20,817 B), as expected.

## On-device acceptance points

`/proc/asound/cards` shows the card; dmesg shows adsp firmware load (rootfs stage) or an explicit
firmware-missing line (rescue stage — expected); no regressions vs v9 in display/touch/battery/
wireless (`tools/r11s_onboard_check.sh`). Rollback = v9 image + original `dtb_v9.dtb`.
