#!/usr/bin/env python3
"""Each channel of a 16-bit stereo WAV from START seconds for LEN seconds: frequency (zero crossings), peak-to-peak.

    tests/wav_stereo.py FILE.wav START LEN     -> "L <Hz> <p-p> R <Hz> <p-p>"
"""
import struct
import sys
import wave

w = wave.open(sys.argv[1])
rate = w.getframerate()
start, length = float(sys.argv[2]), float(sys.argv[3])
w.setpos(int(start * rate))
n = int(length * rate)
d = struct.unpack('<%dh' % (2 * n), w.readframes(n))
res = []
for ch, name in ((0, 'L'), (1, 'R')):
    s = d[ch::2]
    mid = (max(s) + min(s)) / 2
    ups = sum(1 for a, b in zip(s, s[1:]) if a < mid <= b)
    res.append('%s %.0f %d' % (name, ups / length, max(s) - min(s)))
print(' '.join(res))
