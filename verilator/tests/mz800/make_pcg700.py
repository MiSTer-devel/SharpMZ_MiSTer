#!/usr/bin/env python3
"""Write pcg700.mzf: MZ-800 in 700 mode redefines character 01 ('A') in the CG-RAM at C000 as a solid
block and shows it at the top left of the screen (white on blue). Load/exec 2000h."""
code = bytes([
    0xF3,                    # DI
    0x3E, 0x08, 0xD3, 0xCE,  # DMD=08: 700 mode
    0xD3, 0xE3,              # OUT (E3),A    ROM E000 + VRAM D000
    0xDB, 0xE0,              # IN A,(E0)     map the CG-RAM at C000
    0x21, 0x08, 0xC0,        # LD HL,C008    character 01
    0x06, 0x08,              # LD B,8
    0x36, 0xFF, 0x23, 0x10, 0xFB,   # LD (HL),FF; INC HL; DJNZ
    0xDB, 0xE1,              # IN A,(E1)     unmap it
    0x3E, 0x01, 0x32, 0x00, 0xD0,   # LD (D000),01
    0x3E, 0x71, 0x32, 0x00, 0xD8,   # LD (D800),71  white on blue
    0x18, 0xFE,              # JR $
])
ADDR = 0x2000
hdr = bytes([1]) + b'PCG700\r'.ljust(17, b'\r') + len(code).to_bytes(2, 'little') \
    + ADDR.to_bytes(2, 'little') + ADDR.to_bytes(2, 'little')
open('pcg700.mzf', 'wb').write(hdr.ljust(128, b'\0') + code)
