#!/usr/bin/env python3
"""Convert an (Extended) CPC DSK image to D88, marking the sectors single density (FM).

The MZ-80K disk archive (MZ-80FIO / MZ-80FD disks: 35 or 40 tracks, 2 sides, 16 sectors of 128 bytes) was read
with CPDRead in 2004. Its EDSK files don't record the density (track header recording mode 0), so emulators take
the sectors as MFM and the MZ-80K's FM controller (Toshiba T3444M) finds no sector. The header's track size is also
wrong (1100h for 900h tracks), so the tracks are found by their "Track-Info" blocks.

A sector CPDRead could not read (FDC status 1 or 2 not zero) gets the D88 data CRC error status (B0h).
Sector IDs are kept as they are (side 1's IDs say head 0 on these disks; the T3444 does not compare the head).

usage: edsk2d88.py IN.dsk OUT.d88 [--mfm]
"""
import re, struct, sys


def tracks(d):
    """(track, side, [(C, H, R, N, st1, st2, data)]) for each Track-Info block, in file order."""
    out = []
    for off in [m.start() for m in re.finditer(b'Track-Info\r\n', d)]:
        t = d[off:off + 0x100]
        secs, pos = [], off + 0x100
        for s in range(t[0x15]):
            e = t[0x18 + 8 * s:0x20 + 8 * s]
            ln = (e[6] | e[7] << 8) if d[:8] == b'EXTENDED' else (128 << t[0x14])
            secs.append((e[0], e[1], e[2], e[3], e[4], e[5], d[pos:pos + ln]))
            pos += ln
        out.append((t[0x10], t[0x11], secs))
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 2:
        sys.exit(__doc__)
    d = open(args[0], 'rb').read()
    if not (d.startswith(b'EXTENDED CPC DSK') or d.startswith(b'MV - CPC')):
        sys.exit(f'{args[0]}: not a CPC DSK image')
    dens = 0x00 if '--mfm' in sys.argv else 0x40
    body, ptr = bytearray(), [0] * 164
    for trk, side, secs in tracks(d):
        n = trk * 2 + side
        if n >= 164:
            continue
        ptr[n] = 0x2B0 + len(body)
        for c, h, r, sz, st1, st2, data in secs:
            stat = 0xB0 if (st1 or st2) else 0x00
            body += struct.pack('<4BHBBB5xH', c, h, r, sz, len(secs), dens, 0, stat, len(data)) + data
    total = 0x2B0 + len(body)
    hdr = bytearray(0x2B0)
    hdr[0:17] = args[0].rsplit('/', 1)[-1][:16].encode('ascii', 'replace').ljust(17, b'\0')
    hdr[0x1B] = 0x00                                    # 2D
    struct.pack_into('<I', hdr, 0x1C, total)
    struct.pack_into('<164I', hdr, 0x20, *ptr)
    open(args[1], 'wb').write(hdr + body)


if __name__ == '__main__':
    main()
