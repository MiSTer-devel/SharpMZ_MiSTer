#!/usr/bin/env python3
"""MZ-700 video tests (run_tests.sh pcg700_mz700, e2scroll_mz700).

pcg700.mzf: HAL PCG-700 test (registers E010-E012, as idealine's PCG700 programming page).

Programs display code EF in character set 1 (a person) and set 2 (a box) through E010/E011/E012 (strobe bit 4, set
select bit 2), switches the PCG display on (E012 bit 3 = 0), and shows on line 2: EF set 1, "A" (ROM), EF set 2.
With the PCG-700 the two EFs show the two patterns; without, both show the ROM's EF.

e2scroll.mzf: writes a line of text, then reads E250. The MZ-80A scrolls its display on reads of E200-E2FF; the
MZ-700 has nothing there (Metro-Cross reads E200-E2FF in play), so the text must stay where it is.
"""
import os

ORG = 0x1200
code = bytearray()
labels, fix = {}, []

def emit(*b): code.extend(b)
def addr(name): fix.append((len(code), name)); emit(0, 0)
def label(name): labels[name] = ORG + len(code)

EF_ROW = (0xEF - 0x80) * 8                      # the RAM address of code EF's first row (upper 128 characters)
emit(0x21); addr('pat1'); emit(0x11, EF_ROW & 255, EF_ROW >> 8, 0x06, 8, 0x0E, 0x00, 0xCD); addr('prog')
emit(0x21); addr('pat2'); emit(0x11, EF_ROW & 255, EF_ROW >> 8, 0x06, 8, 0x0E, 0x04, 0xCD); addr('prog')
emit(0xAF, 0x32, 0x12, 0xE0)                    # E012 = 0: PCG display on (bit 3 low)
emit(0x21, 0x50, 0xD0, 0x36, 0xEF, 0x23, 0x36, 0x01, 0x23, 0x36, 0xEF)    # VRAM line 2: EF, A, EF
emit(0x21, 0x50, 0xD8, 0x36, 0x71, 0x23, 0x36, 0x71, 0x23, 0x36, 0xF1)    # colour: white on blue; bit 7 = set 2
emit(0x18, 0xFE)                                # JR $
label('prog')                                   # HL = pattern, DE = row address, B = 8, C = set bits (0 or 4)
loop = len(code)
emit(0x7E, 0x32, 0x10, 0xE0)                    # E010 = pattern row
emit(0x7B, 0x32, 0x11, 0xE0)                    # E011 = address low
emit(0x7A, 0xB1, 0xC6, 0x10, 0x32, 0x12, 0xE0)  # E012 = address high | set | strobe
emit(0x7A, 0xB1, 0x32, 0x12, 0xE0)              # E012 = strobe off
emit(0x13, 0x23)
emit(0x10, (loop - (len(code) + 2)) & 255)      # DJNZ
emit(0xC9)
label('pat1'); emit(16, 126, 20, 62, 85, 73, 50, 0)                 # the idealine BASIC example's character
label('pat2'); emit(0xFF, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0xFF)  # a box
for pos, name in fix:
    code[pos], code[pos + 1] = labels[name] & 255, labels[name] >> 8

def mzf(name, code, path):
    hdr = bytearray(128)
    hdr[0] = 1
    hdr[1:17] = name.encode().ljust(16, b'\r')[:16]
    hdr[18:20] = len(code).to_bytes(2, 'little')
    hdr[20:22] = ORG.to_bytes(2, 'little')
    hdr[22:24] = ORG.to_bytes(2, 'little')
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), path)
    open(out, 'wb').write(hdr + bytes(code))
    print(out, len(code), 'bytes')

mzf('PCG700 TEST\r', code, 'pcg700.mzf')

# e2scroll: 'SCROLL TEST' (display codes) on line 1, colour on, then LD A,(E250) and loop.
text = [0x13, 0x03, 0x12, 0x0F, 0x0C, 0x0C, 0x00, 0x14, 0x05, 0x13, 0x14]    # S C R O L L _ T E S T
e2 = bytearray([0x21, 0x28, 0xD0])                    # LD HL,D028
for c in text:
    e2 += bytes([0x36, c, 0x23])                      # LD (HL),c / INC HL
e2 += bytes([0x3A, 0x50, 0xE2, 0x18, 0xFB])           # loop: LD A,(E250) / JR loop
mzf('E2 SCROLL TEST\r', e2, 'e2scroll.mzf')

