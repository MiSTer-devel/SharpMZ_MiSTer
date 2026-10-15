#!/usr/bin/env python3
"""tests/mz1500/psgstereo.mzf: the MZ-1500's two PSGs, one tone each at full volume.

PSG 0 (port F2, left) plays 440 Hz on channel 0, PSG 1 (F3, right) 880 Hz; the other channels and noise are off.
SN76489 at 3.546875 MHz: f = clock / (32 N); N = 252 gives 439.8 Hz, N = 126 879.6 Hz.
run_tests.sh psg_mz1500 records the core's output (--wav-out) and checks each channel's frequency and level.
"""
import os

ORG = 0x1200


def psg(port, n):
    out = bytearray()
    for v in (0x80 | (n & 0x0F), (n >> 4) & 0x3F, 0x90, 0xBF, 0xDF, 0xFF):   # tone 0 = N, volume 0 max, others off
        out += bytes([0x3E, v, 0xD3, port])                                   # LD A,v / OUT (port),A
    return out


code = psg(0xF2, 252) + psg(0xF3, 126) + bytes([0x18, 0xFE])                  # JR $
hdr = bytearray(128)
hdr[0] = 1
hdr[1:17] = b'PSG STEREO\r'.ljust(16, b'\r')
hdr[18:20] = len(code).to_bytes(2, 'little')
hdr[20:22] = ORG.to_bytes(2, 'little')
hdr[22:24] = ORG.to_bytes(2, 'little')
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'psgstereo.mzf')
open(out, 'wb').write(hdr + code)
print(out, len(code), 'bytes')
