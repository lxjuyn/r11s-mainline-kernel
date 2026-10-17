#!/usr/bin/env python3
"""mk_arm64_image_header.py — prefix a 64-byte fake arm64 Image header onto a payload.

For the Oppo R11s (SDM660) ABL->U-Boot chainload entry contract:
ABL decompresses the boot.img kernel field to 0x80080000, reads the arm64 Image
header from the decompressed data (validates image_size < 0x3180000, ignores
kernel_addr), then jumps to 0x80080000 + text_offset.

This wraps a payload (e.g. u-boot.bin, built CONFIG_POSITION_INDEPENDENT=y) so
ABL treats it as a valid arm64 Image:
  - code0      = b +0x40  (branch over the 64-byte header into the payload)
  - text_offset= 0        (entry == 0x80080000)
  - image_size = 64 + len(payload)  (must stay < 0x3180000)
  - magic      = "ARM\\x64"

Usage:
  python3 tools/mk_arm64_image_header.py build/u-boot-sdm660/u-boot.bin > out/uboot_Image
"""
import struct
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: mk_arm64_image_header.py <payload.bin>")

with open(sys.argv[1], "rb") as f:
    blob = f.read()

size = 64 + len(blob)                    # reported image_size; must stay < 0x3180000
hdr = struct.pack("<I", 0x14000010)      # code0: AArch64 `b +0x40` over the 64-byte header
hdr += struct.pack("<I", 0)              # code1
hdr += struct.pack("<Q", 0)              # text_offset (entry = 0x80080000)
hdr += struct.pack("<Q", size)           # image_size
hdr += struct.pack("<Q", 0)              # flags (LE, 4K granule)
hdr += struct.pack("<Q", 0)              # res2
hdr += struct.pack("<Q", 0)              # res3
hdr += struct.pack("<Q", 0)              # res4
hdr += struct.pack("<I", 0x644d5241)     # magic "ARM\x64" (LE bytes 41 52 4d 64)
hdr += struct.pack("<I", 0)              # res5

sys.stdout.buffer.write(hdr + blob)
