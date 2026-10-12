#!/usr/bin/env python3
"""Make a bootable Sharp MZ-700/MZ-800 floppy image (Extended CPC DSK) from an MZF program.

The format is the one the MZ-1E05 floppy ROM and the MZ-800 IPL read: 35 cylinders x 2 heads x
16 sectors of 256 bytes, logical track = cylinder * 2 + head, head 0 on the image's side 1 (the
ROM writes the complemented head number to port DD). The MB8876 has an inverted data bus, so the
image holds every byte inverted.

Logical sector 0 is the boot record: 03 'IPLPRO', name (CR terminated) at +7, size at +14h,
load address at +16h, exec address at +18h, start sector at +1Eh. The program follows from
logical sector 1. Boot it with J F000 (MZ-700 with the MZ-1E05 ROM) or from the MZ-800 IPL.

usage: make_boot_disk.py PROGRAM.mzf OUT.dsk [--cylinders N]
"""
import argparse

ap = argparse.ArgumentParser()
ap.add_argument('mzf')
ap.add_argument('out')
ap.add_argument('--cylinders', type=int, default=35)
a = ap.parse_args()

mzf = open(a.mzf, 'rb').read()
name = mzf[1:18].split(b'\r')[0][:16]
size = int.from_bytes(mzf[0x12:0x14], 'little')
load = int.from_bytes(mzf[0x14:0x16], 'little')
exe = int.from_bytes(mzf[0x16:0x18], 'little')
prog = mzf[128:128 + size]

SECTORS, SSIZE = 16, 256
boot = bytearray(SSIZE)
boot[0] = 3
boot[1:7] = b'IPLPRO'
boot[7:7 + len(name) + 1] = name + b'\r'
boot[0x14:0x16] = size.to_bytes(2, 'little')
boot[0x16:0x18] = load.to_bytes(2, 'little')
boot[0x18:0x1A] = exe.to_bytes(2, 'little')
boot[0x1E:0x20] = (1).to_bytes(2, 'little')

# Logical sectors: 0 = boot record, 1.. = program.
logical = [bytes(boot)] + [prog[i:i + SSIZE].ljust(SSIZE, b'\0') for i in range(0, len(prog), SSIZE)]
assert len(logical) <= a.cylinders * 2 * SECTORS, 'program too big'

tracks = a.cylinders * 2
tsize = 0x100 + SECTORS * SSIZE
disk = bytearray(b'EXTENDED CPC DSK File\r\nDisk-Info\r\n'.ljust(0x22, b'\0'))
disk += b'SharpMZ-MiSTer'.ljust(14, b'\0')
disk += bytes([a.cylinders, 2, 0, 0]) + bytes([tsize >> 8] * tracks)
disk = disk.ljust(0x100, b'\0')
for cyl in range(a.cylinders):
    for side in range(2):                               # image side s = head (1 - s)
        head = 1 - side
        lt = cyl * 2 + head
        info = bytearray(b'Track-Info\r\n'.ljust(0x10, b'\0'))
        info += bytes([cyl, side, 0, 0, 1, SECTORS, 0x4E, 0xE5])
        data = bytearray()
        for r in range(1, SECTORS + 1):
            info += bytes([cyl, side, r, 1, 0, 0]) + SSIZE.to_bytes(2, 'little')
            n = lt * SECTORS + (r - 1)
            sec = logical[n] if n < len(logical) else bytes(SSIZE)
            data += bytes(b ^ 0xFF for b in sec)
        disk += info.ljust(0x100, b'\0') + data
open(a.out, 'wb').write(disk)
print(f'{a.out}: {name.decode("latin-1")!r} {size} bytes load {load:04X} exec {exe:04X}, {len(disk)} bytes')
