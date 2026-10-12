#!/usr/bin/env python3
"""Decode Sharp MZ tape recordings (WAV, or anything ffmpeg reads) into MZF files.

Usage: wav2mzf.py INPUT [OUTDIR]       (OUTDIR defaults to the current directory)

The standard Sharp format (MZ-80K/80A/700/800/1500; sharpmz.net, mz800emu libs/mztape):
each bit is one pulse, long for 1 and short for 0 (MZ-700: about 958 and 518 us). A block is
a tape mark -- 40 long and 40 short pulses before a header, 20 and 20 before a body -- then
one long pulse, the data, a 16-bit checksum (the number of 1 bits, high byte first) and a
long pulse; then 256 short pulses and a second copy of the data and checksum. Each byte is
a long start pulse then 8 bits, most significant first. The header is the 128-byte MZF
header; the body is the number of bytes it gives. A block whose checksum fails is taken
from its copy.

A pulse is high then low; recordings are often inverted, so pulses are measured both from
rising edge to rising edge and from falling edge to falling edge (after removing DC) and the
one that decodes more files is kept. The long/short threshold adapts to the tape speed. One MZF is written per header
and body pair found, named after the header's file name. Turbo and non-standard formats
are not decoded.
"""
import os, subprocess, sys, wave
import array


def read_samples(path):
    """Mono float samples and the sample rate. WAV directly, other formats through ffmpeg."""
    if not path.lower().endswith('.wav'):
        tmp = path + '.tmp.wav'
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', path, '-ac', '1', tmp], check=True)
        try:
            return read_samples(tmp)
        finally:
            os.remove(tmp)
    w = wave.open(path)
    n, ch, sw, rate = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
    raw = w.readframes(n)
    if sw == 1:
        a = [b - 128 for b in raw]
    elif sw == 2:
        a = array.array('h', raw)
    else:
        sys.exit('16-bit or 8-bit WAV only')
    if ch > 1:
        a = [sum(a[i:i + ch]) for i in range(0, len(a), ch)]
    return a, rate


def pulses(samples, rate, edge=1):
    """Periods (seconds) between rising (edge 1) or falling (edge -1) edges, with a running mean for DC
    and a little hysteresis."""
    out = []
    mean = 0.0
    k = 1.0 / (rate * 0.005)                 # 5 ms DC tracker
    peak = 1.0
    state = 0
    last = None
    for i, s in enumerate(samples):
        mean += (s - mean) * k
        v = (s - mean) * edge
        peak = max(peak * 0.9995, abs(v))
        h = peak * 0.1
        if state <= 0 and v > h:
            state = 1
            if last is not None:
                out.append((i - last) / rate)
            last = i
        elif state >= 0 and v < -h:
            state = -1
    return out


def classify(periods):
    """1 for long, 0 for short, using a threshold between the two most common pulse lengths."""
    srt = sorted(p for p in periods if 0.0002 < p < 0.003)
    if not srt:
        return []
    short = srt[len(srt) // 4]               # gaps are mostly short pulses
    thr = short * 1.45
    return [1 if p > thr else 0 for p in periods]


def find_mark(bits, start, n):
    """Index after a tape mark of n long then n short pulses and one long pulse (with some slack)."""
    i = start
    L = len(bits)
    while i < L:
        run = 0
        while i < L and bits[i] == 1:
            run += 1
            i += 1
        if run >= n * 3 // 4:
            j = i
            s = 0
            while j < L and bits[j] == 0:
                s += 1
                j += 1
            if s >= n * 3 // 4 and j < L and bits[j] == 1:
                return j + 1
        i += 1
    return None


def read_bytes(bits, i, count):
    """count bytes (start pulse + 8 bits each) from i; returns (bytes, next index) or None."""
    out = bytearray()
    for _ in range(count):
        if i + 9 > len(bits) or bits[i] != 1:
            return None
        v = 0
        for b in bits[i + 1:i + 9]:
            v = v << 1 | b
        out.append(v)
        i += 9
    return out, i


def read_block(bits, i, size):
    """A block, its checksum and its copy: the data, or None if neither copy checks."""
    r = read_bytes(bits, i, size + 2)
    copies = []
    if r:
        copies.append(r)
        j = r[1] + 1
        while j < len(bits) and bits[j] == 0:     # 256 short pulses
            j += 1
        r2 = read_bytes(bits, j, size + 2)
        if r2:
            copies.append(r2)
    for data, end in copies:
        body, chk = data[:size], data[size] << 8 | data[size + 1]
        if sum(bin(b).count('1') for b in body) & 0xFFFF == chk:
            return bytes(body), end
    return None, (copies[0][1] if copies else i)


def decode(bits):
    files, msgs = [], []
    i = 0
    while True:
        i = find_mark(bits, i, 40)
        if i is None:
            break
        hdr, i = read_block(bits, i, 128)
        if hdr is None:
            msgs.append(f'  header with a bad checksum at pulse {i}, skipped')
            continue
        size = hdr[18] | hdr[19] << 8
        j = find_mark(bits, i, 20)
        if j is None:
            msgs.append('  no body after the last header')
            break
        body, i = read_block(bits, j, size)
        name = hdr[1:18].split(b'\r')[0].decode('ascii', 'replace')
        if body is None:
            msgs.append(f'  {name}: body checksum failed')
            continue
        files.append((name, hdr + body))
    return files, msgs


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    outdir = sys.argv[2] if len(sys.argv) > 2 else '.'
    samples, rate = read_samples(sys.argv[1])
    files, msgs = max((decode(classify(pulses(samples, rate, e))) for e in (1, -1)), key=lambda r: len(r[0]))
    for m in msgs:
        print(m)
    for n, (name, data) in enumerate(files):
        safe = ''.join(c if c.isalnum() or c in ' -_.' else '_' for c in name).strip() or f'file{n}'
        path = os.path.join(outdir, f'{n + 1:02d} {safe}.mzf')
        open(path, 'wb').write(data)
        print(f'{path}: type {data[0]:02x}, {len(data) - 128} bytes, load {data[20] | data[21] << 8:04x}')
    return 0 if files else 1


if __name__ == '__main__':
    sys.exit(main())
