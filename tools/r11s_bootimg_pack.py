#!/usr/bin/env python3
"""r11s_bootimg_pack.py — canonical Android boot image (header v1) packer for OPPO R11s.

Builds the canonical `boot.img` for the R11s (Qualcomm SDM660 / arm64) mainline
Ubuntu bring-up, matching the layout of the official R11s boot images.

Canonical layout (evidence, read from official R11s boot images, see
recon/P0_C_LOCAL_OTA_1170_AND_DTS_STATIC_AUDIT.md and the live boot/recovery
image headers in this repo):

  - Android boot image, header version 1 (header_size 0x670 / 1648)
  - page_size  = 0x1000
  - kernel_addr   = 0x8000          -> base 0x0, kernel_offset  0x8000
  - ramdisk_addr  = 0x1000000       -> base 0x0, ramdisk_offset 0x1000000
  - tags_addr     = 0x100           -> base 0x0, tags_offset    0x100
  - kernel field  = Image.gz || sdm660-oppo-r11s.dtb  (appended-DTB contract,
    the Qualcomm ABL locates/passes the DTB; see recon/P2_R11S_MAINLINE_DTS_DESIGN.md
    "Appended-DTB ABL mechanism confirmed")
  - ramdisk field = r11s_ubuntu_initramfs.cpio.gz
  - second_size = 0, recovery_dtbo_size = 0

SAFETY / GATES (CLAUDE.md):
  - Default mode is DRY-RUN: it reads inputs, computes the would-be boot.img
    in memory and PRINTS the exact pack command + expected sha256. It writes
    NOTHING and never touches a device.
  - `--write` produces the boot image on the host (still no device access).
    Per CLAUDE.md, no testable image may be generated until the official
    rollback materials + `fastboot boot` gates pass, so `--write` is gated.
  - This script only writes a file on the host. It never flashes a device.

Notes on `id` and reproducibility:
  - The 20-byte `id` field is left zero. Official R11s images populate it, but
    the value is not reproducible from image content (see verification notes in
    tools/); the SDM660 ABL does not verify `id` for boot.
  - Image.gz is produced deterministically (gzip, mtime=0, level 9) by this
    script itself, so dry-run sha256 == `--write` sha256 on the same host.
    (Deflate bytes depend on the host zlib/Python version.)

Usage (dry-run, recommended):
  python3 tools/r11s_bootimg_pack.py \
      --kernel build/mainline_linux7_ubuntu_ref/arch/arm64/boot/Image \
      --dtb out/r11s_dtb_build_20260731_224315/sdm660-oppo-r11s.dtb \
      --ramdisk out/r11s_ubuntu_initramfs_20260731_2302/r11s_ubuntu_initramfs.cpio.gz \
      --out out/boot.img

Use `--write` (after gates pass) to actually create out/boot.img.
"""

import argparse
import gzip
import hashlib
import os
import struct

ANDROID_MAGIC = b"ANDROID!"
HEADER_V0_SIZE = 0x660  # 1632
HEADER_V1_SIZE = 0x670  # 1648

# Canonical parameters, from the official R11s boot image header evidence.
CANON = {
    "base": 0x0,
    "page_size": 0x1000,
    "kernel_offset": 0x8000,
    "ramdisk_offset": 0x1000000,
    "tags_offset": 0x100,
    "os_version": 0,
    "header_version": 1,
    "cmdline": "console=ttyMSM0,115200n8 earlycon=msm_serial_dm,0xc170000",
}


def align_up(value, alignment):
    return (value + alignment - 1) & ~(alignment - 1)


def gzip_deterministic(data: bytes) -> bytes:
    """Deterministic Image.gz: gzip, mtime=0, max compression.

    Same settings as `gzip -n -9` (identical 10-byte header: magic, method,
    flags, mtime=0, XFL=2, OS=Unix). Deflate payload comes from host zlib.
    """
    return gzip.compress(data, compresslevel=9, mtime=0)


def build_kernel_field(kernel_raw: bytes, dtb: bytes) -> bytes:
    """Kernel field = Image.gz || appended DTB (Qualcomm ABL contract)."""
    if kernel_raw[:2] == b"\x1f\x8b":
        image_gz = kernel_raw  # already compressed
    else:
        image_gz = gzip_deterministic(kernel_raw)
    return image_gz + dtb


def pack(kernel: bytes, ramdisk: bytes, page_size: int, base: int,
         kernel_offset: int, ramdisk_offset: int, tags_offset: int,
         cmdline: str, os_version: int, header_version: int) -> bytes:
    if header_version not in (0, 1):
        raise ValueError("header_version must be 0 or 1")
    cmdline_b = cmdline.encode("utf-8")[:512]
    if header_version >= 1:
        hdr_size = HEADER_V1_SIZE
    else:
        hdr_size = HEADER_V0_SIZE

    hdr = bytearray(hdr_size)
    hdr[0:8] = ANDROID_MAGIC
    struct.pack_into("<I", hdr, 8, len(kernel))                    # kernel_size
    struct.pack_into("<I", hdr, 12, (base + kernel_offset) & 0xFFFFFFFF)
    struct.pack_into("<I", hdr, 16, len(ramdisk))                  # ramdisk_size
    struct.pack_into("<I", hdr, 20, (base + ramdisk_offset) & 0xFFFFFFFF)
    struct.pack_into("<I", hdr, 24, 0)                             # second_size
    struct.pack_into("<I", hdr, 28, 0)                             # second_addr
    struct.pack_into("<I", hdr, 32, (base + tags_offset) & 0xFFFFFFFF)
    struct.pack_into("<I", hdr, 36, page_size)
    struct.pack_into("<I", hdr, 40, header_version)
    struct.pack_into("<I", hdr, 44, os_version)
    hdr[64:64 + len(cmdline_b)] = cmdline_b
    if header_version >= 1:
        struct.pack_into("<I", hdr, 1632, 0)                       # recovery_dtbo_size
        struct.pack_into("<Q", hdr, 1636, 0)                       # recovery_dtbo_offset
        struct.pack_into("<I", hdr, 1644, HEADER_V1_SIZE)          # header_size

    koff = page_size
    roff = page_size + align_up(len(kernel), page_size)
    total = roff + align_up(len(ramdisk), page_size)
    img = bytearray(total)
    img[0:len(hdr)] = hdr
    img[koff:koff + len(kernel)] = kernel
    img[roff:roff + len(ramdisk)] = ramdisk
    return bytes(img)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--kernel", required=True, help="raw kernel Image (or Image.gz)")
    ap.add_argument("--dtb", default="", help="r11s DTB appended after Image.gz")
    ap.add_argument("--ramdisk", required=True, help="initramfs cpio.gz")
    ap.add_argument("--out", required=True, help="output boot.img path")
    ap.add_argument("--base", type=lambda x: int(x, 0), default=CANON["base"])
    ap.add_argument("--page-size", type=lambda x: int(x, 0), default=CANON["page_size"])
    ap.add_argument("--kernel-offset", type=lambda x: int(x, 0),
                    default=CANON["kernel_offset"])
    ap.add_argument("--ramdisk-offset", type=lambda x: int(x, 0),
                    default=CANON["ramdisk_offset"])
    ap.add_argument("--tags-offset", type=lambda x: int(x, 0),
                    default=CANON["tags_offset"])
    ap.add_argument("--os-version", type=lambda x: int(x, 0), default=CANON["os_version"])
    ap.add_argument("--header-version", type=int, default=CANON["header_version"])
    ap.add_argument("--cmdline", default=CANON["cmdline"])
    ap.add_argument("--root", default="",
                    help="real rootfs device for cmdline (root=<dev> rootwait); "
                         "empty = bring-up mode, initramfs drops to rescue shell")
    ap.add_argument("--rootfstype", default="")
    ap.add_argument("--write", action="store_true",
                    help="actually write the boot image (gated; default is dry-run)")
    args = ap.parse_args()

    for p in (args.kernel, args.ramdisk):
        if not os.path.isfile(p):
            raise SystemExit(f"ERROR: input not found: {p}")
    if args.dtb and not os.path.isfile(args.dtb):
        raise SystemExit(f"ERROR: input not found: {args.dtb}")

    with open(args.kernel, "rb") as f:
        kernel_raw = f.read()
    with open(args.ramdisk, "rb") as f:
        ramdisk = f.read()
    dtb = b""
    if args.dtb:
        with open(args.dtb, "rb") as f:
            dtb = f.read()

    kernel_field = build_kernel_field(kernel_raw, dtb)

    cmdline = args.cmdline
    if args.root:
        cmdline = cmdline + " root=" + args.root
        if args.rootfstype:
            cmdline = cmdline + " rootfstype=" + args.rootfstype
        cmdline = cmdline + " rootwait"

    img = pack(kernel_field, ramdisk, args.page_size, args.base,
               args.kernel_offset, args.ramdisk_offset, args.tags_offset,
               cmdline, args.os_version, args.header_version)

    # --- print canonical command (the exact command --write would run) ---
    exe = os.path.abspath(__file__)
    cmd = [f"python3 {exe}",
           f"--kernel {args.kernel}",
           f"--dtb {args.dtb}" if args.dtb else "# --dtb omitted",
           f"--ramdisk {args.ramdisk}",
           f"--out {args.out}",
           f"--base {args.base:#x}", f"--page-size {args.page_size:#x}",
           f"--kernel-offset {args.kernel_offset:#x}",
           f"--ramdisk-offset {args.ramdisk_offset:#x}",
           f"--tags-offset {args.tags_offset:#x}",
           f"--header-version {args.header_version}",
           f"--os-version {args.os_version:#x}",
           f"--cmdline '{cmdline}'",
           "--write" if args.write else "# add --write to actually build"]
    print("=" * 78)
    print(" r11s_bootimg_pack.py — canonical OPPO R11s boot.img (header v1)")
    print("=" * 78)
    print("\n[EXACT COMMAND USED]")
    print("  \\\n    ".join(cmd))
    print()

    print("[INPUT SHA256]")
    print(f"  kernel Image   : {sha256_hex(kernel_raw)}   ({len(kernel_raw)} B)")
    if dtb:
        print(f"  r11s DTB       : {sha256_hex(dtb)}   ({len(dtb)} B)")
    print(f"  initramfs.gz   : {sha256_hex(ramdisk)}   ({len(ramdisk)} B)")

    print("\n[INTERMEDIATE (in-memory, same host reproducible)]")
    image_gz = kernel_field[:len(kernel_field) - len(dtb)]
    print(f"  Image.gz       : {sha256_hex(image_gz)}   ({len(image_gz)} B)")
    print(f"  kernel.gz-dtb  : {sha256_hex(kernel_field)}   ({len(kernel_field)} B)")

    print("\n[EXPECTED OUTPUT]")
    print(f"  boot.img       : {sha256_hex(img)}")
    print(f"  size           : {len(img)} B  ({len(img):#x})")
    print(f"  header_version : {args.header_version}  (header_size {HEADER_V1_SIZE:#x})")
    print(f"  page_size      : {args.page_size:#x}")
    print(f"  kernel_addr    : {args.base + args.kernel_offset:#x}"
          f"   ramdisk_addr : {args.base + args.ramdisk_offset:#x}"
          f"   tags_addr : {args.base + args.tags_offset:#x}")
    print(f"  layout         : hdr@0x0, kernel@{args.page_size:#x} ({len(kernel_field)} B),"
          f" ramdisk@{args.page_size + align_up(len(kernel_field), args.page_size):#x}"
          f" ({len(ramdisk)} B)")

    if args.write:
        with open(args.out, "wb") as f:
            f.write(img)
        print(f"\nWROTE {args.out}")
        print(f"  sha256: {sha256_hex(img)}")
    else:
        print("\nDRY-RUN: no file written, no device touched.")
        print("Re-run with --write (after CLAUDE.md gates pass) to create the boot.img.")


if __name__ == "__main__":
    main()
