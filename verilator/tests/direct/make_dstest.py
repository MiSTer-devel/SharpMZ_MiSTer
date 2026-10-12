#!/usr/bin/env python3
"""Make dstest.mzf, the Load Direct start test (run_tests.sh ds_*).

The program runs from its own MZF header, as Jumpin' Jack and Antiriad do: exec is 1108, in the header's comment
area, and the body (16 bytes of 5A) loads at 1170. It stores, at 2000:
  2000  the first name byte from the header at 10F1 ('D', 44)
  2001  the first body byte from 1170 (5A)
  2002  SP as the program found it (F0 10)
then loops. With Load Direct: Start Program this needs the header put back at 10F0 after the boot and SP=10F0.
"""
import os

code = bytes([
    0x3A, 0xF1, 0x10,        # LD A,(10F1)
    0x32, 0x00, 0x20,        # LD (2000),A
    0x3A, 0x70, 0x11,        # LD A,(1170)
    0x32, 0x01, 0x20,        # LD (2001),A
    0x21, 0x00, 0x00,        # LD HL,0
    0x39,                    # ADD HL,SP
    0x22, 0x02, 0x20,        # LD (2002),HL
    0x18, 0xFE,              # JR $
])
body = bytes([0x5A] * 16)
hdr = bytearray(128)
hdr[0] = 0x01
name = b'DSTEST\r'
hdr[1:1 + len(name)] = name
hdr[18:20] = len(body).to_bytes(2, 'little')
hdr[20:22] = (0x1170).to_bytes(2, 'little')
hdr[22:24] = (0x1108).to_bytes(2, 'little')
hdr[24:24 + len(code)] = code
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dstest.mzf')
open(out, 'wb').write(bytes(hdr) + body)
print(out)
