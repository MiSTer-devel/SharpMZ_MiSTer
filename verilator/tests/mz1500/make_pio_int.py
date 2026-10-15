#!/usr/bin/env python3
"""tests/mz1500/pioint.mzf: Z80 PIO interrupts from the 8253's OUT0, as Batten Tanuki sets them up.

IM 2, vector table at B900 (I = B9, PIO vector 00) -> handler. PIO port A (control FC): bit mode, bit 4 (/CTC0 =
8253 OUT0) the only interrupt input, active high; enabled. 8253 counter 0 mode 0, count 037F (about 1 ms at
895 kHz), gate on (E008 bit 0). The handler reloads the count (mode 0: OUT0 falls, then rises at terminal count),
increments a 16-bit count at B800 and shows its high byte at D000 (display code), EI, RETI.
The main loop shows the low byte at D001. Run it for some seconds: the count must keep going up.
"""
import os

ORG = 0x1200
c = bytearray()
c += bytes([0xF3, 0xED, 0x5E])                            # DI ; IM 2
c += bytes([0x31, 0x00, 0xB0])                            # LD SP,B000 (0000-0FFF is ROM)
c += bytes([0x3E, 0x01, 0x32, 0x08, 0xE0])                # LD A,1 ; LD (E008),A   gate 0 on
c += bytes([0x21, 0x00, 0x00, 0x22, 0x00, 0xB8])          # LD HL,0 ; LD (B800),HL
HANDLER_AT = None
c += bytes([0x21, 0x00, 0x00, 0x22, 0x00, 0xB9])          # LD HL,handler ; LD (B900),HL   (patched below)
hpatch = len(c) - 5
c += bytes([0x3E, 0xB9, 0xED, 0x47])                      # LD A,B9 ; LD I,A
c += bytes([0x0E, 0xFC])                                  # LD C,FC
for v in (0x00, 0xCF, 0x3F, 0x37, 0xEF):                  # vector, bit mode, I/O mask, int control (mask follows), mask
    c += bytes([0x3E, v, 0xED, 0x79])                     # LD A,v ; OUT (C),A
c += bytes([0x3E, 0x30, 0x32, 0x07, 0xE0])                # counter 0 mode 0, LSB then MSB
c += bytes([0x3E, 0x7F, 0x32, 0x04, 0xE0, 0x3E, 0x03, 0x32, 0x04, 0xE0])
c += bytes([0x3E, 0x83, 0xED, 0x79])                      # PIO A: interrupts on
c += bytes([0xFB])                                        # EI
loop = ORG + len(c)
c += bytes([0x3A, 0x00, 0xB8, 0x32, 0x01, 0xD0])          # loop: LD A,(B800) ; LD (D001),A
c += bytes([0x18, 0xF8])                                  # JR loop
handler = ORG + len(c)
c[hpatch] = handler & 0xFF; c[hpatch + 1] = handler >> 8
c += bytes([0xF5, 0xE5])                                  # PUSH AF ; PUSH HL
c += bytes([0x3E, 0x7F, 0x32, 0x04, 0xE0, 0x3E, 0x03, 0x32, 0x04, 0xE0])   # reload counter 0
c += bytes([0x2A, 0x00, 0xB8, 0x23, 0x22, 0x00, 0xB8])   # LD HL,(B800) ; INC HL ; LD (B800),HL
c += bytes([0x7C, 0x32, 0x00, 0xD0])                      # LD A,H ; LD (D000),A
c += bytes([0xE1, 0xF1, 0xFB, 0xED, 0x4D])                # POP HL ; POP AF ; EI ; RETI
hdr = bytearray(128)
hdr[0] = 1
hdr[1:17] = b'PIO INT\r'.ljust(16, b'\r')
hdr[18:20] = len(c).to_bytes(2, 'little')
hdr[20:22] = ORG.to_bytes(2, 'little')
hdr[22:24] = ORG.to_bytes(2, 'little')
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pioint.mzf')
open(out, 'wb').write(hdr + c)
print(out, len(c), 'bytes; handler at %04X' % handler)
