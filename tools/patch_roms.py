#!/usr/bin/env python3
"""Add ROMs that romtool's layout has no place for to the combined ROM images, and rewrite their MIFs.
Run after romtool (build_meminitfiles.sh).

  combined_mrom  0x1C000: the 16 KB MZ-800 ROM (1Z-013B, CG, IPL/9Z-504M).
  combined_mrom  0x10800: the MZ-700 FDC ROM banks (F000-FFFF): the MZ-1E05 floppy interface ROM.
  combined_mrom  0x17800: the MZ-2000 IPL banks (40 and 80 column): MZ2000_IPL.rom (MAME mz20ipl.bin, CRC d7ccf37f).
  combined_mrom  0x11800: MZ-1500 9Z-502M monitor (banks 23h/24h) and E800/F000/F800 (27h-29h), the old MZ-800 slots;
                          ROMs from mz800emu (ROM_MZ1500_0000/E000).
  combined_cgrom 0x5000:  the MZ-1500 CG (4 KB, CG bank Ah), bit-reversed from mz800emu's copy.
  combined_cgrom 0x3000:  the MZ-800 CG (the MZ-700 CG with each byte bit-reversed).
  combined_cgrom 0x4800:  the MZ-2000 CG with katakana (MAME font.bin, CRC 6ae6ce8e; rebuilt from EmuZ-2000 bitmaps,
                          MAME marks it BAD_DUMP). The MZ-80B keeps MZFONT (the export font) at 0x4000.

usage: patch_roms.py ROMDIR MIFDIR
"""
import sys

romdir, mifdir = sys.argv[1], sys.argv[2]


def read(name):
    return open(f"{romdir}/{name}", "rb").read()


def patch(name, offset, data, size=None):
    rom = bytearray(read(f"{name}.rom"))
    if size:
        rom += bytes(size - len(rom))
    rom[offset:offset + len(data)] = data
    open(f"{romdir}/{name}.rom", "wb").write(rom)
    with open(f"{mifdir}/{name}.mif", "w") as f:
        f.write(f"DEPTH = {len(rom)};\nWIDTH = 8;\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\nCONTENT BEGIN\n")
        for a in range(0, len(rom), 16):
            f.write(f"{a:04x}: " + " ".join(f"{b:02x}" for b in rom[a:a + 16]) + ";\n")
        f.write("END;\n")


mz800 = read("MZ800_0000.rom") + read("MZ800_CGROM.rom") + read("MZ800_E000.rom")
assert len(mz800) == 0x4000
patch("combined_mrom", 0x1C000, mz800, 0x20000)
# MROM_BANK "100001"/"100010" (sharpmz.vhd) = MZ-700 F000-F7FF / F800-FFFF.
fd700 = read("MZ-1E05.rom")
assert len(fd700) == 0x1000
patch("combined_mrom", 0x21 * 0x800, fd700)
# MROM_BANK "101111"/"110000" = MZ-2000 IPL, 40/80 column.
ipl2000 = read("MZ2000_IPL.rom")
assert len(ipl2000) == 0x800
patch("combined_mrom", 0x2F * 0x800, ipl2000)
patch("combined_mrom", 0x30 * 0x800, ipl2000)
patch("combined_cgrom", 0x3000, read("MZ800_CGROM.rom"))
# MZ-1500 (MROM_BANK clauses in sharpmz.vhd).
m1500 = read("MZ1500_0000.rom"); e1500 = read("MZ1500_E000.rom")
assert len(m1500) == 0x1000 and len(e1500) == 0x2000
patch("combined_mrom", 0x23 * 0x800, m1500)
patch("combined_mrom", 0x27 * 0x800, e1500[0x800:0x2000])
# CG_BANK "1001" (video_vc.vhd) = MZ-2000.
cg2000 = read("MZ2000_CGROM.rom")
assert len(cg2000) == 0x800
patch("combined_cgrom", 0x4800, cg2000)
# CG_BANK "1010" = MZ-1500 (4 KB).
# mz800emu stores it bit-reversed (MSB = rightmost pixel), like its MZ-800 CG; the MZ-700 renderer wants MSB left.
patch("combined_cgrom", 0x5000, bytes(int(f"{v:08b}"[::-1], 2) for v in read("MZ1500_CGROM.rom")), 0x6000)
