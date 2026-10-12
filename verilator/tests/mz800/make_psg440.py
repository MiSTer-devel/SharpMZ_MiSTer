#!/usr/bin/env python3
"""Write psg440.mzf: MZ-800 PSG channel 0 at N=252 (3546900/32/252 = 439.8 Hz), full volume. Load/exec 2000h."""
code = bytes([
    0x3E, 0x8C, 0xD3, 0xF2,  # tone 0, low 4 bits of N (C)
    0x3E, 0x0F, 0xD3, 0xF2,  # high 6 bits of N (0F) -> N = FC
    0x3E, 0x90, 0xD3, 0xF2,  # volume 0 = 0 (loudest)
    0x18, 0xFE,              # JR $
])
ADDR = 0x2000
hdr = bytes([1]) + b'PSG440\r'.ljust(17, b'\r') + len(code).to_bytes(2, 'little') \
    + ADDR.to_bytes(2, 'little') + ADDR.to_bytes(2, 'little')
open('psg440.mzf', 'wb').write(hdr.ljust(128, b'\0') + code)
