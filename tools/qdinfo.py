#!/usr/bin/env python3
"""List the blocks of a Quick Disk image (.qdf dump or .mzq) and check their CRCs.

A QD side is a byte stream. Each block is preceded by sync characters (16 16) and is
    A5, then either one byte (the first block: the number of blocks that follow; a formatted
    disk also has a one-byte A5 00 mark)
    or a flag byte, a 16-bit length (little endian) and that many data bytes,
and ends with a CRC-16 (polynomial 0xA001 reflected, init 0, over A5 and the block)
sent low byte first. Flag 00 is a file's 64-byte header (type, 17-byte name, 2 bytes,
size, load, exec), 05 its body.

    tools/qdinfo.py IMAGE
"""
import sys


def crc16(data):
    c = 0
    for b in data:
        c ^= b
        for _ in range(8):
            c = (c >> 1) ^ 0xA001 if c & 1 else c >> 1
    return c


def blocks(img):
    """Yield (offset, kind, payload, crc_ok) for each block found after a sync pair.

    A one-byte block (A5 n CRC) is the block count when it comes first, otherwise a mark
    (a freshly formatted disk has A5 00 after the count); which form a block has is decided
    by its CRC."""
    i = 0
    first = True
    while True:
        j = img.find(b'\x16\x16\xa5', i)
        if j < 0:
            return
        a = j + 2
        crc_at = lambda e: img[e] | img[e + 1] << 8 if e + 1 < len(img) else -1
        if crc16(img[a:a + 2]) == crc_at(a + 2):
            yield a, 'count' if first else 'mark', img[a + 1:a + 2], True
            end = a + 2
        else:
            flag = img[a + 1]
            n = img[a + 2] | img[a + 3] << 8
            end = a + 4 + n
            kind = {0: 'header', 5: 'body'}.get(flag, 'flag %02x' % flag)
            yield a, kind, img[a + 4:end], crc16(img[a:end]) == crc_at(end)
        first = False
        i = end + 2


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    img = open(sys.argv[1], 'rb').read()
    if img.startswith(b'-QD format-'):
        img = img[16:]
    bad = 0
    for off, kind, payload, ok in blocks(img):
        bad += not ok
        info = ''
        if kind == 'count':
            info = 'blocks %d' % payload[0]
        elif kind == 'mark':
            info = '%02x' % payload[0]
        elif kind == 'header' and len(payload) >= 26:
            name = payload[1:18].split(b'\r')[0].decode('ascii', 'replace')
            size = payload[20] | payload[21] << 8
            load = payload[22] | payload[23] << 8
            exe = payload[24] | payload[25] << 8
            info = 'type %02x "%s" size %04x load %04x exec %04x' % (payload[0], name, size, load, exe)
        else:
            info = '%d bytes' % len(payload)
        print('%6d  %-7s %-50s %s' % (off, kind, info, 'CRC ok' if ok else 'CRC BAD'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
