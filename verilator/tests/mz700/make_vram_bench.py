#!/usr/bin/env python3
"""tests/mz700/vbench.mzf: MZ-700 VRAM access speed. Marks D001 (start), writes VRAM 30000 times in a tight loop
(LD (HL),A to a blank cell, so the picture doesn't change), marks D002 (end), then loops. The frames between the
two marks measure the CPU's VRAM throughput, which the MZ-700's GDG limits to about one access per drawn line
(mz800emu: mz700_vramctrl.h). Compare the core with mz800emu: frame-log hash changes at the two marks."""
import os
ORG = 0x1200
c = bytes([0xF3,                          # DI
           0x3E, 0x02, 0x32, 0x01, 0xD0,  # LD A,2 ; LD (D001),A   start mark
           0x01, 0x30, 0x75,              # LD BC,30000
           0x21, 0x00, 0xD2,              # LD HL,D200            a blank cell
           0xAF,                          # XOR A
           0x77,                          # loop: LD (HL),A
           0x0B,                          # DEC BC
           0x78, 0xB1,                    # LD A,B ; OR C
           0x3E, 0x00,                    # LD A,0
           0x20, 0xF8,                    # JR NZ,loop
           0x3E, 0x03, 0x32, 0x02, 0xD0,  # LD A,3 ; LD (D002),A   end mark
           0x18, 0xFE])                   # JR $
hdr = bytearray(128)
hdr[0] = 1
name = b'VBENCH'
hdr[1:1 + len(name)] = name
hdr[1 + len(name)] = 0x0D
hdr[18:20] = len(c).to_bytes(2, 'little')
hdr[20:22] = ORG.to_bytes(2, 'little')
hdr[22:24] = ORG.to_bytes(2, 'little')
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vbench.mzf')
open(out, 'wb').write(bytes(hdr) + c)
print(out)
