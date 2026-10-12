#!/usr/bin/env python3
"""Put a replacement monitor ROM into a copy of the core's system ROM, for OSD ROM and RAM > Load System ROM.

Usage: make_monitor_rom.py MODEL MONITOR.rom OUT.rom [--80col] [--base combined_mrom.rom]

Load System ROM writes the file from offset 0 of the core's 128 KB system ROM (rtl/software/roms/combined_mrom.rom).
A 4 KB MZ-80K monitor can be loaded as it is: offset 0 is the MZ-80K 40-column monitor. For any other model, or for
the 80-column monitor, this script writes a full 128 KB image with the monitor at that model's offset; load OUT.rom
instead. Press Reset (OSD Reset) after loading: the CPU keeps running the old monitor until then.

Offsets (monitor at 0000-0FFF, as rtl/sharpmz.vhd's MROM_BANK maps them):
  model   40 columns  80 columns
  mz80k   0x00000     0x01000
  mz80c   0x03800     0x04800
  mz1200  0x07000     0x08000
  mz80a   0x0A800     0x0B800
  mz700   0x0E000     0x0F000
The MZ-800 (0x1C000, one 16 KB ROM), MZ-1500, MZ-80B and MZ-2000 IPLs are laid out differently; see patch_roms.py.
The replacement lasts until the core is loaded again (the ROM is block RAM initialised from the RBF).
"""
import argparse, os, sys

OFFSETS = {'mz80k': (0x00000, 0x01000), 'mz80c': (0x03800, 0x04800), 'mz1200': (0x07000, 0x08000),
           'mz80a': (0x0A800, 0x0B800), 'mz700': (0x0E000, 0x0F000)}

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument('model', choices=sorted(OFFSETS))
ap.add_argument('monitor')
ap.add_argument('out')
ap.add_argument('--80col', dest='col80', action='store_true', help='replace the 80-column monitor instead')
ap.add_argument('--base', default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                               '../rtl/software/roms/combined_mrom.rom'))
a = ap.parse_args()

rom = bytearray(open(a.base, 'rb').read())
mon = open(a.monitor, 'rb').read()
if len(mon) > 4096:
    sys.exit(f'{a.monitor}: {len(mon)} bytes; a monitor is at most 4096 (0000-0FFF)')
off = OFFSETS[a.model][1 if a.col80 else 0]
rom[off:off + len(mon)] = mon
open(a.out, 'wb').write(rom)
print(f'{a.out}: {len(rom)} bytes, {a.monitor} at 0x{off:05X} ({a.model}, {"80" if a.col80 else "40"} columns)')
