#!/usr/bin/env python3
"""Put MZF files on a Quick Disk image (.qdf) for the MZ-1500 (and MZ-800 with a QD drive).

Usage: mzf2qdf.py OUT.qdf FILE.mzf|FILE.mzt [...]     (every record of an .mzt goes on the disk)

The layout copies the commercial dumps: 16-byte "-QD format-" header, then
    00 x4826, 16 x9, A5 <block count> CRC, 16 x5, 00 x2795,
and per file
    16 x9, A5 00 <64-byte header> CRC, 16 x6, 00 x255, 16 x10, A5 05 <length> <body> CRC, 16 x6, 00 x255
padded with zeros to 81920 bytes of medium. The QD header is the MZF header's type,
name, then two zero bytes before size, load and exec. The CRC is CRC-16 (0xA001
reflected, init 0) over A5 and the block, low byte first (see tools/qdinfo.py).
"""
import sys

MEDIUM = 81920


def crc16(data):
    c = 0
    for b in data:
        c ^= b
        for _ in range(8):
            c = (c >> 1) ^ 0xA001 if c & 1 else c >> 1
    return c


def block(body):
    b = b'\xa5' + body
    c = crc16(b)
    return b + bytes([c & 0xFF, c >> 8])


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    files = []
    for name in sys.argv[2:]:
        d = open(name, 'rb').read()
        i = 0
        while i + 128 <= len(d) and d[i]:              # an MZT holds several MZF records; type 0 ends it
            size = d[i + 18] | d[i + 19] << 8
            hdr = bytes(d[i:i + 18]) + b'\x00\x00' + bytes(d[i + 18:i + 24])
            hdr += bytes(64 - len(hdr))
            files.append((hdr, d[i + 128:i + 128 + size]))
            i += 128 + size

    m = bytes(4826) + b'\x16' * 9 + block(bytes([2 * len(files)])) + b'\x16' * 5 + bytes(2795)
    for hdr, body in files:
        m += b'\x16' * 9 + block(b'\x00' + bytes([64, 0]) + hdr) + b'\x16' * 6 + bytes(255)
        m += b'\x16' * 10 + block(b'\x05' + bytes([len(body) & 0xFF, len(body) >> 8]) + body)
        m += b'\x16' * 6 + bytes(255)
    if len(m) > MEDIUM:
        print('too much for one side: %d bytes, %d fit' % (len(m), MEDIUM))
        return 1
    with open(sys.argv[1], 'wb') as f:
        f.write(b'-QD format-' + b'\xff' * 5 + m + bytes(MEDIUM - len(m)))
    print('%s: %d file(s), %d of %d bytes used' % (sys.argv[1], len(files), len(m), MEDIUM))
    return 0


if __name__ == '__main__':
    sys.exit(main())
