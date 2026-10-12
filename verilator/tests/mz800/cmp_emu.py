#!/usr/bin/env python3
"""Compare a simulation screenshot with an mz800emu --crop canvas screenshot (640x200).
A 320 wide simulation image is doubled horizontally. Channels may differ by up to 20
(the core has 4 bits per channel). Prints the mismatch count and a few positions."""
import struct, sys, zlib


def load(path):
    d = open(path, 'rb').read()
    i, idat = 8, b''
    while i < len(d):
        n, = struct.unpack('>I', d[i:i + 4]); t = d[i + 4:i + 8]; c = d[i + 8:i + 8 + n]
        if t == b'IHDR': w, h, bd, ct = struct.unpack('>IIBB', c[:10])
        if t == b'IDAT': idat += c
        i += 12 + n
    raw = zlib.decompress(idat); bpp = 3 if ct == 2 else 4; stride = w * bpp
    rows, prev = [], bytearray(stride)
    for y in range(h):
        ft = raw[y * (stride + 1)]; line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0; b = prev[x]; cc = prev[x - bpp] if x >= bpp else 0
            if ft == 1: line[x] = (line[x] + a) & 255
            elif ft == 2: line[x] = (line[x] + b) & 255
            elif ft == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif ft == 4:
                p = a + b - cc; pa, pb, pc = abs(p - a), abs(p - b), abs(p - cc)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else cc)) & 255
        rows.append([tuple(line[x * bpp:x * bpp + 3]) for x in range(w)]); prev = line
    return w, h, rows


sw, sh, sim = load(sys.argv[1])
ew, eh, emu = load(sys.argv[2])
if sw == 320:
    sim = [[p for p in r for _ in (0, 1)] for r in sim]
bad = [(x, y) for y in range(min(sh, eh)) for x in range(640)
       if any(abs(a - b) > 20 for a, b in zip(sim[y][x], emu[y][x]))]
print(f'{len(bad)} mismatches' + (f', first {bad[:5]} sim {sim[bad[0][1]][bad[0][0]]} emu {emu[bad[0][1]][bad[0][0]]}' if bad else ''))
sys.exit(1 if bad else 0)
