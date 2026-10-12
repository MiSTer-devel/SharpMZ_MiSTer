#!/usr/bin/env python3
"""Make a blank Extended DSK floppy image, every byte E5h (an empty CP/M disk).

Usage: make_blank_dsk.py OUT.dsk [1440|720|360]

  1440  80 tracks, 2 sides, 18 x 512-byte sectors (CP/M 4.1 HD drive C:, OSD Floppy > Drive B Unit: 3rd)
  720   80 tracks, 2 sides,  9 x 512
  360   40 tracks, 2 sides,  9 x 512

The MZ-800 CP/M 4.1 1440K drive wants a CP/M-formatted disk; the MS-DOS-formatted "_Vzor" templates show
"Disk full" there.
"""
import sys

GEOM = {'1440': (80, 2, 18), '720': (80, 2, 9), '360': (40, 2, 9)}


def make(tracks, sides, spt, size_code=2):
    ssize = 128 << size_code
    tsize = 256 + spt * ssize
    hdr = bytearray(256)
    sig = b"EXTENDED CPC DSK File\r\nDisk-Info\r\n"
    hdr[0:len(sig)] = sig
    hdr[0x22:0x22 + 14] = b"SharpMZ-MiSTer"
    hdr[0x30] = tracks
    hdr[0x31] = sides
    for i in range(tracks * sides):
        hdr[0x34 + i] = tsize >> 8
    out = bytearray(hdr)
    for t in range(tracks):
        for s in range(sides):
            ti = bytearray(256)
            ti[0:12] = b"Track-Info\r\n"
            ti[0x10], ti[0x11] = t, s
            ti[0x14], ti[0x15], ti[0x16], ti[0x17] = size_code, spt, 0x4E, 0xE5
            for k in range(spt):
                e = 0x18 + 8 * k
                ti[e:e + 8] = bytes([t, s, k + 1, size_code, 0, 0, ssize & 0xFF, ssize >> 8])
            out += ti + b'\xe5' * (spt * ssize)
    return bytes(out)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    g = sys.argv[2] if len(sys.argv) > 2 else '1440'
    data = make(*GEOM[g])
    open(sys.argv[1], 'wb').write(data)
    print(f"{sys.argv[1]}: {g} KB, {len(data)} bytes")
