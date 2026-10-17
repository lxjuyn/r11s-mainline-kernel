#!/usr/bin/env python3
"""mkbootimg_v1.py — minimal Android boot image (header v1) packer for OPPO R11s.

Builds a header-v1 Android boot image from a kernel (Image.gz + appended DTB)
and an optional ramdisk, matching the parameter layout of the official
R11s C.19 boot.img (page_size 0x1000, kernel_addr base+0x8000,
ramdisk_addr base+0x1000000, tags_addr base+0x100).

Usage:
  python3 mkbootimg_v1.py --kernel KERNEL.GZ-DTB --ramdisk INITRD.CPIO.GZ \
      --out boot.img [--base 0x0] [--page-size 0x1000] \
      [--kernel-offset 0x8000] [--ramdisk-offset 0x1000000] \
      [--tags-offset 0x100] [--cmdline "..."] [--os-version 0] \
      [--header-version 1]

This tool only writes a boot image file on the host. It never flashes a device.
"""

import argparse
import struct

ANDROID_MAGIC = b"ANDROID!"


def align_up(value, alignment):
    return (value + alignment - 1) & ~(alignment - 1)


def pack(kernel: bytes, ramdisk: bytes, page_size: int,
         base: int, kernel_offset: int, ramdisk_offset: int,
         tags_offset: int, cmdline: bytes, os_version: int,
         header_version: int) -> bytes:
    if header_version not in (0, 1):
        raise ValueError("header_version must be 0 or 1")
    if len(cmdline) > 512:
        raise ValueError("cmdline too long")

    header_size = page_size        # header occupies page 0
    koff = page_size
    klen = len(kernel)
    roff = koff + align_up(klen, page_size)
    rlen = len(ramdisk)
    total = roff + align_up(rlen, page_size)

    img = bytearray(total)
    img[0:8] = ANDROID_MAGIC
    img[8:12] = struct.pack("<I", klen)                 # kernel_size
    img[12:16] = struct.pack("<I", (base + kernel_offset) & 0xFFFFFFFF)
    img[16:20] = struct.pack("<I", rlen)                # ramdisk_size
    img[20:24] = struct.pack("<I", (base + ramdisk_offset) & 0xFFFFFFFF)
    img[24:28] = struct.pack("<I", 0)                   # second_size
    img[28:32] = struct.pack("<I", 0)                   # second_addr
    img[32:36] = struct.pack("<I", (base + tags_offset) & 0xFFFFFFFF)
    img[36:40] = struct.pack("<I", page_size)
    img[40:44] = struct.pack("<I", header_version)
    img[44:48] = struct.pack("<I", os_version)
    # name (offset 0x30-0x3F) all zero
    img[64:64 + len(cmdline)] = cmdline                 # cmdline offset 0x40
    # header v1 tail fields (0x660-0x670)
    if header_version >= 1:
        img[1632:1636] = struct.pack("<I", 0)           # recovery_dtbo_size
        img[1636:1644] = struct.pack("<Q", 0)           # recovery_dtbo_offset
        img[1644:1648] = struct.pack("<I", 0x670)       # header_size = 1648

    img[koff:koff + klen] = kernel
    img[roff:roff + rlen] = ramdisk
    return bytes(img)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--ramdisk", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--base", type=lambda x: int(x, 0), default=0x0)
    ap.add_argument("--page-size", type=lambda x: int(x, 0), default=0x1000)
    ap.add_argument("--kernel-offset", type=lambda x: int(x, 0), default=0x8000)
    ap.add_argument("--ramdisk-offset", type=lambda x: int(x, 0), default=0x1000000)
    ap.add_argument("--tags-offset", type=lambda x: int(x, 0), default=0x100)
    ap.add_argument("--cmdline",
                    default="console=ttyMSM0,115200n8 "
                            "earlycon=msm_serial_dm,0xc170000")
    ap.add_argument("--os-version", type=lambda x: int(x, 0), default=0)
    ap.add_argument("--header-version", type=int, default=1)
    args = ap.parse_args()

    with open(args.kernel, "rb") as f:
        kernel = f.read()
    ramdisk = b""
    if args.ramdisk:
        with open(args.ramdisk, "rb") as f:
            ramdisk = f.read()

    img = pack(kernel, ramdisk, args.page_size, args.base,
               args.kernel_offset, args.ramdisk_offset, args.tags_offset,
               args.cmdline.encode("utf-8"), args.os_version,
               args.header_version)
    with open(args.out, "wb") as f:
        f.write(img)
    print(f"wrote {args.out}: {len(img)} bytes, "
          f"kernel={len(kernel)} ramdisk={len(ramdisk)}")


if __name__ == "__main__":
    main()
