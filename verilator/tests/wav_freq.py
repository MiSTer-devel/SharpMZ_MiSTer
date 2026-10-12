#!/usr/bin/env python3
"""Print the frequency of a 16-bit mono WAV between START and START+LEN seconds (rising mean crossings)."""
import struct, sys

path, start, length = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
data = open(path, 'rb').read()[44:]
s = struct.unpack('<%dh' % (len(data) // 2), data)
seg = s[int(start * 48000):int((start + length) * 48000)]
mean = sum(seg) / len(seg)
edges = [i for i in range(1, len(seg)) if seg[i - 1] < mean <= seg[i]]
print('%.1f' % ((len(edges) - 1) * 48000 / (edges[-1] - edges[0])) if len(edges) > 1 else 0)
