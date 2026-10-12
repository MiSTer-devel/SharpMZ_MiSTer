#!/usr/bin/env python3
"""Write gfx320.mzf: MZ-800 320x200 4-colour test (load/exec 2000h, outside the CG ROM window at 1000h)."""
code = bytes([
    0xF3,                    # DI
    0xAF, 0xD3, 0xCE,        # XOR A; OUT (CE),A     DMD=0: 320x200, 4 colours, 800 mode
    0xDB, 0xE0,              # IN A,(E0)             map VRAM at 8000
    0x3E, 0x00, 0xD3, 0xF0,  # palette 0 = 0 (black)
    0x3E, 0x1A, 0xD3, 0xF0,  # palette 1 = 10 (light red)
    0x3E, 0x2C, 0xD3, 0xF0,  # palette 2 = 12 (light green)
    0x3E, 0x3F, 0xD3, 0xF0,  # palette 3 = 15 (white)
    0x3E, 0x01, 0xD3, 0xCC,  # WF: single write, plane I
    0x21, 0x00, 0x80,        # LD HL,8000
    0x01, 0xA0, 0x0F,        # LD BC,4000 (100 lines)
    0x36, 0xFF, 0x23, 0x0B, 0x78, 0xB1, 0x20, 0xF8,   # fill with FF
    0x3E, 0x02, 0xD3, 0xCC,  # WF: single write, plane II
    0x21, 0x00, 0x80,        # LD HL,8000
    0x01, 0x40, 0x1F,        # LD BC,8000 (200 lines)
    0x36, 0x0F, 0x23, 0x0B, 0x78, 0xB1, 0x20, 0xF8,   # fill with 0F
    0x18, 0xFE,              # JR $
])
ADDR = 0x2000
hdr = bytes([1]) + b'GFX320\r'.ljust(17, b'\r') + len(code).to_bytes(2, 'little') \
    + ADDR.to_bytes(2, 'little') + ADDR.to_bytes(2, 'little')
open('gfx320.mzf', 'wb').write(hdr.ljust(128, b'\0') + code)
