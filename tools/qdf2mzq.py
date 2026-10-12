#!/usr/bin/env python3
"""Convert a raw Quick Disk dump (.qdf: 16-byte "-QD format-" header, then the disk's byte stream with
gaps, sync marks and real CRCs) into mz800emu's compact .mzq.

A disk is a sequence of blocks, each after a sync mark (16 16 ...):
  first block:  A5, block count, CRC(2)
  file blocks:  A5, type (00 = MZF header, 05 = body), size (2, LE), data[size], CRC(2)
An .mzq stores each block as 00 16 16 A5 + the same fields + "CRC" (mz800emu qdisk.h).

usage: qdf2mzq.py IN.qdf OUT.mzq
"""
import sys

src = open(sys.argv[1], 'rb').read()
if src[:3] == b'-QD':
    src = src[16:]

out = bytearray()
pos = 0
first = True
while True:
    j = src.find(b'\x16\x16', pos)
    if j < 0:
        break
    k = j
    while k < len(src) and src[k] == 0x16:
        k += 1
    if k >= len(src) or src[k] != 0xA5:
        pos = k
        continue
    k += 1
    if first:
        count = src[k]
        out += b'\x00\x16\x16\xa5' + bytes([count]) + b'CRC'
        pos = k + 3
        first = False
        print(f'header: {count} blocks')
        continue
    btype = src[k]
    size = src[k + 1] | (src[k + 2] << 8)
    data = src[k + 3:k + 3 + size]
    if len(data) < size:
        break
    out += b'\x00\x16\x16\xa5' + bytes([btype, size & 0xFF, size >> 8]) + data + b'CRC'
    desc = data[1:18].split(b'\r')[0].decode('latin-1', 'replace') if btype == 0 else ''
    print(f'block type {btype:02X} size {size:5d} {desc}')
    pos = k + 3 + size + 2

open(sys.argv[2], 'wb').write(out)
print(f'{sys.argv[2]}: {len(out)} bytes')
