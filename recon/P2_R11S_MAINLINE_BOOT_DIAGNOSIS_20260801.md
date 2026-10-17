# P2 — R11s Mainline Boot Diagnosis — Overnight Consolidation

> Date: 2026-08-01. Author: overnight workflow consolidation.
> Scope: consolidate the 10 overnight findings on why the mainline (7.2-rc5)
> kernel is rejected by the R11s ABL while the 4.19 boot-debug kernel boots.
> This document records facts, hashes and file paths only. **No kernel, DTS or
> rootfs was modified.** All hashes below are re-verified from the files on disk
> on 2026-08-01.
>
> Device state at time of recording: fastboot `secure=yes`, `unlocked=yes`,
> `product=sdm660`; boot partition restored to boot-debug.img and booting
> Lineage 20 (`adb = lineage_R11s`). 9008/EDL remains recovery-only and was
> never used.

---

## 0. Executive summary

**Root cause (confirmed by arithmetic + ABL source):** the R11s ABL rejects a
boot image when the *decompressed* kernel's **arm64 Image-header `image_size`
field** does not fit the ABL's fixed kernel→DTB load window:

```
if ((KernelLoadAddr + Kptr->ImageSize) >= DeviceTreeLoadAddr)
    -> "Dtb header can get corrupted due to runtime kernel size"
    -> EFI_BAD_BUFFER_SIZE -> return to fastboot
```

With the R11s ABL PCDs (offsets from base `0x80000000`):

| Item | Offset (PCD) | Effective address |
|---|---:|---:|
| KernelLoadAddress | `0x00080000` | `0x80080000` |
| DeviceTreeLoadAddress | `0x03200000` | `0x83200000` |
| Window `[0x80080000, 0x83200000)` | — | `0x03180000` = **51,904,512 B (49.5 MiB)** |

Kernel `image_size` fields measured from the actual images:

| Kernel | image_size field | end addr | vs window | verdict |
|---|---:|---:|---|---|
| **mainline 7.2** (Image, SHA `23de027d…`) | `0x3190000` = 51,970,048 B | `0x83210000` | **over by 64 KiB** | **REJECTED** |
| boot-debug 4.19 (downstream) | `0x2cf8000` = 47,153,152 B | `0x82d78000` | spare 4.53 MiB | boots |
| official C.19 4.4 | `0x27c7000` = 41,709,568 B | `0x82847000` | spare 9.72 MiB | boots |
| 4.19 local reference rebuild | `0x3103000` = 51,392,512 B | `0x83183000` | spare 500 KiB | not flashed |

The mainline 7.2 Ubuntu-config kernel misses the window by exactly 64 KiB —
which explains **all 6 mainline combos** returning to fastboot regardless of
DTB, gzip format, qcom tags, padding, or header fields.

**Remaining work:** build a leaner mainline (or sdm660-mainline fork) kernel so
its `image_size` field < 51,904,512 B (needs ≥ 64 KiB reduction; a config cut
of the fat Ubuntu reference config is the obvious lever — see §8/§12), and
corroborate the rejection string directly on the device from the
`logdump`/`logfs` partitions (root required, §11).

---

## 1. Device and tooling facts (fastboot, read-only)

`/home/<user>/claude/r11/recon/p1_fastboot_readonly_20260730_040128/fastboot_getvar_all.txt`

- `unlocked:yes`, `secure:yes`, `product:sdm660`
- `max-download-size:536870912` (512 MiB)
- `partition-type:boot:raw`, `partition-size:boot: 0x4000000` (64 MiB)
- `partition-type:logdump:raw`, `partition-size:logdump: 0x4000000` (64 MiB)  → §11
- `partition-type:logfs:raw`,    `partition-size:logfs:    0x800000` (8 MiB)   → §11

Rollback chain (verified 2026-08-01, `backups/products/products_r11s_flash_rollback_20260801_0125/`):

| Object | SHA-256 |
|---|---|
| official C.19 `boot.img` | `5949396d14aa8113cbd47e0963fb056f1c5e47c182419be29d681651bc1c0dec` |
| `boot-debug.img` (current working Lineage boot) | `4ff811c37070540f0d0fa8fcb1c49d14ee44f3a4e62991fe761f0b1e08d1a7a4` |

---

## 2. Finding 1 — `fastboot boot` (RAM boot) is NOT supported

- Command `fastboot boot out/r11s_ubuntu_mainline_boot.img` →
  **`FAILED (remote: 'unknown command')`**.
- Upload itself succeeded (`Sending OKAY`, 16160 KB); the R11s ABL simply has no
  `boot` (RAM-boot) command.
- Device unharmed: remained in fastboot, `secure=yes`, `unlocked=yes`.
- Implication: the *only* verification path is a persistent
  `fastboot flash boot` of the boot partition.
- Source: `/home/<user>/claude/r11/out/test_flash_progress.md` lines 53–61;
  `recon/P0_B_FASTBOOT_EVIDENCE_REPORT.md`; `STATUS.md` §2026-08-01.

## 3. Finding 2 — flash path works; unsigned test images are accepted

- `fastboot flash boot boot-debug.img` → **boots to Lineage 20**
  (`adb = lineage_R11s`, USB `18d1:4ee7`).
- The ABL accepts unsigned boot images (boot-debug is unsigned), so signature is
  not a variable.
- Source: `out/test_flash_progress.md` lines 69–75.

## 4. Finding 3 — all 6 mainline combos return to fastboot

Every experiment: `fastboot flash boot <img>` → reboot → **back to fastboot**.
All six kernels are the same mainline 7.2-rc5 Image (with Ubuntu arm64 config);
only DTB / gzip / padding / header vary.

| # | Combo image | Kernel | DTB / header variant | SHA-256 |
|---|---|---|---|---|
| 1 | `out/r11s_ubuntu_mainline_boot.img` (v1) | 7.2 Image.gz | our mainline DTB, **no** qcom tags | `54ed462e417316c31e86eba24539ba842093f1dc6fba5f2ff64afa4c6e2a4d11` |
| 2 | `out/r11s_ubuntu_mainline_boot_v2.img` (v2) | 7.2 Image.gz | our DTB + injected `qcom,board-id=<8 0 17011>`, `qcom,msm-id=<317 0>`, pmic-id | `d6f8c7519b002a4d69972dcd5c10e149d574dbdcb6b7c3c4d3c37a14172f2d6a` |
| 3 | `out/comboA_mainline_kernel_official_dtb.img` | 7.2 Image.gz | **official C.19 FDT[3]** (full qcom tags, 17011) | `d93c7a6a73f2cb30c64c3a95c8d2c5cce4ebefa882eae227951411d949a8857d` |
| 4 | `out/comboB_v3gzip_official_dtb.img` | 7.2 Image.gz (`gzip -n -9`, same header as boot-debug) | official FDT[3] | `0a6584678966bd99f633f359bbcc4225e8064c9c0a21b1905fcf1f55a674a6a5` |
| 5 | `out/r11s_ubuntu_mainline_boot_v3_padded.img` | 7.2 `Image_padded_v3` (0x80000 leading pad) | official DTB | `e8a5f93d0828b716e9c8843b763fcf6a1f36581b227d85f683f5c6a11d755767` |
| 6 | `out/comboE_bdheader_mainline_kernel.img` | 7.2 padded kernel | boot-debug full header (`os_version`, `id[32]`) + Ubuntu ramdisk | `549dc06b824abd32cb4f3da385cab3eb9a765f789c9e631b4d1ac3248a329e82` |

Also prepared (flash outcome **not recorded** in `test_flash_progress.md`, file
mtime 02:43 > last status 02:42):
`out/r11s_boot_r11t_params.img`, SHA
`7d026f45dc98795f72d70f858d42e958fe496dc2ed597fedbe890f920cc9c66c`, built with
R11T packer params (§8): base `0x80000000`, kernel_addr `0x80008000`,
ramdisk_addr `0x83000000`, tags `0x80000100`, `os_version`/`os_patch_level`
9.0.0/2019-09.

Controls that boot: `boot-debug.img` (4.19, §0 table). Source:
`out/test_flash_progress.md` lines 77–95, 104–117; `out/boot_combo_test_matrix.md`.

## 5. Finding 4 — ABL loads at `0x80000` via PCD and ignores header `kernel_addr`

From the `wf-abl-load-address` workflow against the R11s ABL
(`QcomModulePkg` `BootLinux.c` / `QcomModulePkg.dec`):

- `KernelLoadAddr = BaseMem() | PcdGet32(KernelLoadAddress = 0x80000)`.
- ABL gzip-decompresses `Image.gz` to `KernelLoadAddr` and jumps there.
- **The boot-header `kernel_addr` field is ignored** (ours was `0x8000`
  for base 0; R11T-style `0x80008000` for base `0x80000000` — neither changes
  the ABL load point).
- The load window is bounded by `DeviceTreeLoadAddr - KernelLoadAddr`
  (= `0x3180000`, §0).

Sources: `out/test_flash_progress.md` lines 126–139 and 178–194.

## 6. Finding 5 — `text_offset`: 0x80000 (working kernels) vs 0 (mainline 7.2)

Measured from the arm64 Image header (magic `41524d64` = `"ARM\x64"` at offset
0x38; `text_offset` u64 @0x08, `image_size` u64 @0x10):

| Kernel image | code0 (offset 0) | text_offset | image_size | decompressed size |
|---|---:|---:|---:|---:|
| mainline 7.2 `Image` (SHA `23de027d…`) | `4d5a40fa` = **MZ** | `0x0` | `0x3190000` (51,970,048 B) | 51,128,832 B |
| boot-debug 4.19 (gzip SHA `59347321…`) | `148e0000` = **`b stext`** | `0x80000` | `0x2cf8000` (47,153,152 B) | 43,018,256 B |
| official C.19 4.4 (decomp SHA `b4232b55…`) | `14660000` = **`b stext`** | `0x80000` | `0x27c7000` (41,709,568 B) | 37,799,944 B |
| 4.19 local ref `build/p1_linux-4.19.325_arm64/…/Image` | `148e0000` = **`b stext`** | `0x80000` | `0x3103000` (51,392,512 B) | 51,392,512 B |

**Correction (important):** `text_offset` is **not** the rejection cause.
The R11T kernel (7.0.14, §8) also has `text_offset = 0` yet boots on the same
ColorOS ABL family, and the ABL source check never reads `text_offset`
(that check list is from Pixel-3-era ABLs). The initial
"text_offset 0 vs 0x80000" hypothesis is superseded by the image_size check
(§0). Source: `out/test_flash_progress.md` lines 83–94, 156–163, 191.

## 7. Finding 6 — code0: raw branch vs MZ/PE-EFI

- Working kernels (4.4/4.19 downstream): `code0` = a real AArch64 branch
  (`b stext`), downstream builds have CONFIG_EFI off.
- Mainline 7.2 with our Ubuntu config: `CONFIG_EFI=y`, `CONFIG_EFI_STUB=y`,
  `CONFIG_EFI_GENERIC_STUB=y` (verified in
  `build/mainline_linux7_ubuntu_ref/.config`). Its `code0` is the
  `efi_signature_nop` = `ccmp x18, #0, #0xd, pl` (`0xfa405a4d`), whose opcode
  spells the PE/COFF magic **"MZ"**; the real entry is `b primary_entry` at
  offset 4 (`code1`). See
  `/home/<user>/claude/r11/linux/arch/arm64/kernel/head.S` lines ~55–72 and
  `/home/<user>/claude/r11/linux/arch/arm64/kernel/efi-header.S` (`efi_signature_nop`).
- A bootloader that jumps to `code0` still lands on a harmless `ccmp` then the
  `b primary_entry`, so MZ-code0 is *bootable* by a raw-jump loader.
- **Not the acceptance differentiator either:** the R11T 7.0.14 fork's `head.S`
  has the identical `efi_signature_nop` + `text_offset=0` layout and boots on
  the same ABL family. It only becomes relevant *after* ABL acceptance (kernel
  actually running), not to the ABL gate.
- Sources: local Image-header hexdump (this report), `head.S`/`efi-header.S`,
  R11T fork `head.S`, `out/test_flash_progress.md`.

## 8. Finding 7 — decompression-buffer / kernel-size check (the root cause)

Hypothesis evolution:

1. "Error in decompression: Output buffer full" (ABL string) → size limit.
2. Buffer-size test compared the *actual decompressed bytes* (48.8 MB mainline)
   against the ramdisk window and seemed to fit → **hypothesis initially
   discarded**.
3. Refined check found in ABL `BootLinux.c`:
   `if ((KernelLoadAddr + Kptr->ImageSize) >= DeviceTreeLoadAddr)` → rejects.
   This uses the **`image_size` header field** (0x3190000 = 49.56 MiB), not the
   file byte-count.

Numbers (§0 table): mainline end addr `0x83210000` ≥ `0x83200000` → **over by
exactly 0x10000 = 64 KiB → EFI_BAD_BUFFER_SIZE → fastboot**. boot-debug fits
with 4.53 MiB to spare; official C.19 fits with 9.72 MiB to spare. The 4.19
local reference rebuild would fit too (500 KiB spare) — it was never flashed.

This single check explains all 6 combos (including v3 padding and combo E,
which changed packer/header/base/tags and still failed). Fix: reduce mainline
`image_size` < 51,904,512 B (need ≥ 64 KiB cut; since `image_size` is
rounded/2 MiB-aligned upstream, budget a real ~2 MiB config cut).

Sources: `out/test_flash_progress.md` lines 156–194. Note on provenance: the
ABL error string and check are attributed from the open-source `QcomModulePkg`
`BootLinux.c` (workflow `wf-abl-load-address` / `wf-boot-image-diff`); the
device ABL binary itself is **not** in our evidence archive, so the string-level
confirmation is source-based, while the arithmetic is fully verified against the
images. On-device confirmation is open via §11.

## 9. Finding 8 — R11T precedent (CPH1707-Mainline, sdm660-mainline fork)

Evidence artifacts:
- `/home/<user>/claude/r11/out/r11t-kernel.tar.gz` (260,551,019 B, SHA
  `12784867e7b45f3345c5693e499afeb184ef6070f50f5bf4e2f19eab3a6d1283`) — source
  of `linux-sdm660-oppor11-t-qcom-sdm660-7.0.y`, **Linux 7.0.14** (fork of the
  mainline sdm660 bring-up line, not a pure upstream 7.0).

Key facts from the fork:
- `arch/arm64/boot/dts/qcom/sdm660-oppo-r11t.dts` (CPH1707 R11T) includes
  `sdm660-xiaomi-jason.dts`, **retains the qcom DTB-selection tags**:
  `qcom,msm-id = <0x13d 0>`, `qcom,board-id = <8 0 0x3eb3>`
  (board-id **16051**, i.e. R11T is a *different* device from R11s 17011/0x4273 —
  it is an ABL-behavior precedent, not a hardware twin), `qcom,pmic-id`; and
  fixes the OPPO PIL layout (mpss 0x8ac00000/adsp 0x92a00000/mba 0x94a00000/
  cdsp 0x94c00000).
- `arch/arm64/configs/sdm660_defconfig` (975 lines — lean) with
  `CONFIG_RANDOMIZE_BASE=y`, `CONFIG_EFI_ZBOOT=y`,
  `CONFIG_CMDLINE_DROP_DANGEROUS_ANDROID_OPTIONS=y`.
- CI builds `Image.gz` from `sdm660_defconfig` and packages via postmarketOS
  (`.github/workflows/build-images.yml`); the boot-image params (reported by
  workflow, external `build-arch-boot-image.sh`) are:
  `--base 0x80000000`, `--kernel_offset 0x8000` → kernel_addr `0x80008000`,
  `--ramdisk_offset 0x03000000`, `--os_version 9.0.0 --os_patch_level 2019-09`,
  `--header_version 1`, kernel field = `cat Image.gz <dtb>`.

Interpretation (with corrections):
- R11T boots the same ColorOS ABL family, so its `base 0x80000000` + lean
  `sdm660_defconfig` is a working reference packaging recipe.
- The `base 0x80000000` was initially treated as the "breakthrough", but ABL
  ignores header `kernel_addr` (§5), so base alone does not change ABL behavior.
  The operative difference is the **leaner config → smaller `image_size`**,
  which is consistent with the §0 window check. **Caveat:** we do **not** have
  R11T's built `Image` in the archive, so R11T's actual `image_size` under this
  exact window is **unverified**; treat R11T as a strong precedent, not proof.
- Source: this report's tarball inspection; `out/test_flash_progress.md`
  lines 141–194.

## 10. Finding 9 — qcom tags (`qcom,msm-id` / `qcom,board-id` / `qcom,pmic-id`)

- These are the tags the Qualcomm ABL uses to select/validate the appended DTB
  (and to match the device board). The R11T fork keeps them in the DTS for the
  stock bootloader's DTB selection (§9).
- Our v2 injected tags byte-identical to the official C.19 FDT[3]
  (`qcom,board-id=<8 0 17011>` / `0x4273`, `qcom,msm-id=<317 0>`, matching
  `qcom,pmic-id`) — **still failed**.
- Combo A used the *entire official* C.19 FDT[3] (full tags) — **still failed**.
- Conclusion: qcom tags are **necessary for ABL DTB selection but not the
  rejection gate**; the rejection is the image_size check (§0).
- Mainline `qcom.yaml` forbids `qcom,msm-id`/`qcom,board-id` for sdm660, so any
  tag injection must stay in the packaging step (post-compile DTB patch), never
  in upstream source. Source: `recon/P2_R11S_MAINLINE_DTS_EVIDENCE_20260801.md`
  lines 58–62; `out/test_flash_progress.md` lines 74, 79, 123.

## 11. Finding 10 — `logdump` / `logfs`: untapped on-device ABL log source

The only on-device record of *why* ABL rejected each image is the bootloader's
own log store, which is present on this device and **untapped**:

- fastboot: `partition-type:logdump:raw` size `0x4000000` (64 MiB);
  `partition-type:logfs:raw` size `0x800000` (8 MiB)
  (`recon/p1_fastboot_readonly_20260730_040128/fastboot_getvar_all.txt` lines 34–35, 58–59).
- ADB read-only block-device listing:
  `logdump -> /dev/block/mmcblk0p58`, `logfs -> /dev/block/mmcblk0p46`
  (`recon/p0_adb_readonly_20260730_033057/adb_readonly_dump.txt` lines 94–95).
- Reading these requires **root** on the running Lineage system (`adb root`,
  or `su` shell), then `dd` from the block device or reading the mounted ABL
  log. A Grep of the local C.19 `boot.img`, `boot-debug.img`, `recovery.img`,
  and OZIP-extracted `boot.img` for the ABL strings
  ("Dtb header can get corrupted…", "Output buffer full") found **none** — the
  ABL binary lives in the `abl` partition, not in boot images, so the on-device
  log is the only direct confirmation path.
- Highest-value next evidence step: dump `logdump`/`logfs` (root) after one
  controlled rejection to capture the exact ABL error string and confirm the §0
  kernel-size verdict on-device.

## 12. Corrected hypothesis timeline (as of 2026-08-01 02:43)

| Hypothesis | Status | Evidence |
|---|---|---|
| DTB content / missing board-id | **refuted** (v2 injected tags; combo A official DTB) | §4, §10 |
| gzip header/FLG/MTIME difference | **refuted** (combo B, `gzip -n -9`) | §4 |
| header `os_version`/`id[32]` zero | **refuted** (combo E copies boot-debug header) | §4 |
| base address / packing params | **refuted** (ABL ignores header `kernel_addr`; combo E) | §5 |
| `text_offset` 0 vs 0x80000 | **refuted** (ABL never reads it; R11T text_offset=0 boots) | §6 |
| `code0` branch vs MZ/EFI | **refuted as acceptance gate** (R11T MZ boots) | §7 |
| decompression "Output buffer full" | **refined** → image_size field vs kernel→DTB window | §8 |
| **image_size field ≥ window → EFI_BAD_BUFFER_SIZE → fastboot** | **confirmed** | §0, §8 |

## 13. Recommended next steps (all require per-action approval where flashing)

1. Build a leaner mainline Image: cut the Ubuntu reference config
   (`CONFIG_ARM64_VA_BITS=52`, `CONFIG_DEBUG_INFO*`, EFI/gadget extras as
   needed) so the built `image_size` field < 51,904,512 B (target ≥ 2 MiB
   headroom); re-measure the header field before any flash.
2. Alternative: use the sdm660-mainline fork (R11T line, §9) as the kernel base
   and drop our R11s DTS in — matches the R11T precedent exactly.
3. Re-flash boot-debug.img as rollback control after each experiment.
4. (Read-only, highest evidence value) with user approval, `adb root` the
   Lineage system and dump `logdump`/`logfs` (§11) to capture the real ABL
   rejection string.
5. Do not modify kernel/DTS/rootfs as part of this diagnostic; the next build
   is a separate, gated task.

## 14. Key files and hashes index

Logs / status:
- `/home/<user>/claude/r11/out/test_flash_progress.md` (live test log, 194 lines)
- `/home/<user>/claude/r11/out/boot_combo_test_matrix.md` (combo design + header diff)
- `/home/<user>/claude/r11/out/wf_bootimg_verify.md` (v1 boot.img structure)
- `/home/<user>/claude/r11/STATUS.md` (2026-08-01 overnight section)
- `/home/<user>/claude/r11/recon/P2_R11S_MAINLINE_DTS_EVIDENCE_20260801.md`
- `/home/<user>/claude/r11/recon/P2_R11S_MAINLINE_DTS_DESIGN.md`

Scripts (read-only analyzers / packers):
- `/home/<user>/claude/r11/out/analyze_boot_fdt.py`
- `/home/<user>/claude/r11/tools/r11s_fastboot_boot_test.sh`, `tools/r11s_bootimg_pack.py`, `tools/mkbootimg_v1.py`

Artifacts (SHA-256):
- mainline `Image` `backups/products/products_mainline_linux7_ubuntu_reference_20260731_2223/Image` = `23de027d37e06403379619bd65276cf7851a2d8fabaf6767f646026a4c1212bf` (51,128,832 B)
- `Image.gz` `backups/products/products_r11s_ubuntu_mainline_20260801_0155/Image.gz` = `2e676f33ea469c8292fffc6109d09b991d110d1f8277fb87633e2ae2c9c8850e`
- our DTB (pre-inject) = `a7b109f7348f946ea383f926fdc5c4b9100eb0461eba7a39e7896b1d5ccf20ed`; injected = `77ee6f75c061ea6abd18bf0e4088cda0d691e0e286d13be1d8466cbe82d04f38`
- initramfs `…/r11s_ubuntu_initramfs.cpio.gz` = `af5bb948e50c57c4d2cc59223fce5284e1343c99ff487d113417bcfa78c61c46`
- 6 combo images: §4 table
- `out/r11s_boot_r11t_params.img` = `7d026f45dc98795f72d70f858d42e958fe496dc2ed597fedbe890f920cc9c66c`
- `out/r11t-kernel.tar.gz` = `12784867e7b45f3345c5693e499afeb184ef6070f50f5bf4e2f19eab3a6d1283`
- rollback: official `boot.img` = `5949396d…`; `boot-debug.img` = `4ff811c3…` (§1)

Kernel sources (unmodified):
- `/home/<user>/claude/r11/linux` (7.2-rc5; `arch/arm64/kernel/head.S`, `arch/arm64/kernel/efi-header.S`)
- `/home/<user>/claude/r11/linux-4.19.325` (4.19 reference)
- `/home/<user>/claude/r11/android_kernel_oppo_sdm660_source_d9391f88aa90` (downstream 4.19)
- `/home/<user>/claude/r11/out/r11t-kernel.tar.gz` (R11T 7.0.14 fork)
- `/home/<user>/claude/r11/build/mainline_linux7_ubuntu_ref/.config` (Ubuntu config; `CONFIG_EFI=y`, `CONFIG_EFI_STUB=y`, `CONFIG_ARM64_VA_BITS=52`)

Live-device evidence:
- `/home/<user>/claude/r11/recon/p1_fastboot_readonly_20260730_040128/fastboot_getvar_all.txt`
- `/home/<user>/claude/r11/recon/p0_adb_readonly_20260730_033057/adb_readonly_dump.txt`

## 15. Safety / scope note

This is a diagnosis record. No kernel/DTS/rootfs/boot image was modified by the
authoring of this document. All device operations described (§2–§4) were the
user-authorized overnight flash tests already recorded in `out/test_flash_progress.md`;
the device is back on boot-debug.img and boots Lineage. 9008/EDL is recovery-only
and was never used. Any future build/flash remains gated on explicit per-action
approval with the §1 rollback chain.
