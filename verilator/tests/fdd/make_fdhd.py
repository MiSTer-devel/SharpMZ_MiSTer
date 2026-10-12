#!/usr/bin/env python3
"""Make tests/fdd/fdhd.mzf: write and read back a sector 1.45 MB into a 1.44 MB disk (MZ-800 floppy interface).

Drive unit 2 (the drive B slot with --fdd-b-hd / OSD Drive B Unit: 3rd), restore, seek track 79, side 1, write
sector 17 with bytes (i ^ 5A), read it back to 3000h. Status after restore, seek, write, read at 2FF2-2FF5, the
track register at 2FF6, bytes written at 2FF8, the read end address at 2FF0. Runs at 2000h from the monitor.
The MZ floppy bus is inverted: the program complements every byte it moves through the FDC, as CP/M does.
"""
import os
ORG = 0x2000
c = bytearray(); labels = {}; fix = []
def emit(*b): c.extend(b)
def L(n): labels[n] = ORG + len(c)
def jr(op, n): emit(op, 0); fix.append((len(c) - 1, n))
def delay(): emit(0x06, 0x00, 0x10, 0xFE)                   # status is valid a few us after a command
def cmd(v): emit(0x3E, 255 - v, 0xD3, 0xD8); delay()
def wait_ready(n): L(n); emit(0xDB, 0xD8, 0x2F, 0x0F); jr(0x38, n)
def save_status(a): emit(0xDB, 0xD8, 0x2F, 0x32, a & 0xFF, a >> 8)
def xfer(name, write):
    L(name); emit(0xDB, 0xD8, 0x2F, 0xCB, 0x4F); jr(0x20, name + 'd')   # DRQ
    emit(0x0F); jr(0x38, name); jr(0x18, name + 'e')                   # busy, else done
    L(name + 'd')
    if write: emit(0x7D, 0xEE, 0x5A, 0x2F, 0xD3, 0xDB, 0x23)            # OUT (DB), ~(L ^ 5A); INC HL
    else:     emit(0xDB, 0xDB, 0x2F, 0x77, 0x23)                        # (HL) = ~IN (DB); INC HL
    jr(0x18, name); L(name + 'e')
emit(0x3E, 0x86, 0xD3, 0xDC); delay()                         # motor, unit 2
cmd(0x08); wait_ready('w1'); save_status(0x2FF2)              # restore
emit(0x3E, 255 - 79, 0xD3, 0xDB)
cmd(0x18); wait_ready('w2'); save_status(0x2FF3)              # seek 79
emit(0xDB, 0xD9, 0x2F, 0x32, 0xF6, 0x2F)                      # track register
emit(0x3E, 0x01, 0xD3, 0xDD)                                  # side 1
emit(0x3E, 255 - 17, 0xD3, 0xDA)                              # sector 17
emit(0x21, 0x00, 0x00); cmd(0xA0); xfer('wl', True)
save_status(0x2FF4); emit(0x22, 0xF8, 0x2F)
emit(0x21, 0x00, 0x30); cmd(0x80); xfer('rl', False)
save_status(0x2FF5); emit(0x22, 0xF0, 0x2F)
emit(0x3E, 0x00, 0xD3, 0xDC)
L('end'); jr(0x18, 'end')
for pos, n in fix:
    off = labels[n] - (ORG + pos + 1); assert -128 <= off < 128, n; c[pos] = off & 0xFF
hdr = bytearray(128); hdr[0] = 1; nm = b'FDHD\r'; hdr[1:1 + len(nm)] = nm
hdr[18:20] = len(c).to_bytes(2, 'little'); hdr[20:22] = ORG.to_bytes(2, 'little'); hdr[22:24] = ORG.to_bytes(2, 'little')
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fdhd.mzf')
open(out, 'wb').write(bytes(hdr) + bytes(c)); print(out, len(c))
