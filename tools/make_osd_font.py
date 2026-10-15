#!/usr/bin/env python3
"""Font and character table for the tape message overlay (rtl/tape_osd.sv).

  tape_osd_font.hex  the MZ-700 character generator's first 256 glyphs (8 bytes each, leftmost pixel in bit 7),
                     indexed by display code
  tape_osd_a2d.hex   Sharp ASCII -> display code, the MZ-700 monitor 1Z-013A's table (ROM 0A92)

usage: make_osd_font.py   (from the repo root; writes rtl/software/mif/)
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROMS = os.path.join(ROOT, 'rtl/software/roms')
OUT = os.path.join(ROOT, 'rtl/software/mif')
cg = open(os.path.join(ROMS, 'MZ700_cgrom.rom'), 'rb').read()[:2048]
mon = open(os.path.join(ROMS, 'monitor_1Z-013A.rom'), 'rb').read()[0xA92:0xA92 + 256]
open(os.path.join(OUT, 'tape_osd_font.hex'), 'w').write('\n'.join('%02x' % b for b in cg) + '\n')
open(os.path.join(OUT, 'tape_osd_a2d.hex'), 'w').write('\n'.join('%02x' % b for b in mon) + '\n')
print('wrote', len(cg), 'glyph bytes and', len(mon), 'table entries')
