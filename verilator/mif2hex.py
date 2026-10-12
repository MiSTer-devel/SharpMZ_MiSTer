#!/usr/bin/env python3
"""Convert an Altera .mif to a $readmemh file (one word per line).

Usage: mif2hex.py in.mif out.hex

Handles "ADDR : v v v ... ;" lines (several words per line) and
"[A..B] : v ;" ranges. Hex radix only, which is all the core's MIFs use.
"""
import re
import sys


def main(src, dst):
    text = open(src).read()
    depth = int(re.search(r'DEPTH\s*=\s*(\d+)', text).group(1))
    width = int(re.search(r'WIDTH\s*=\s*(\d+)', text).group(1))
    for radix in re.findall(r'(ADDRESS_RADIX|DATA_RADIX)\s*=\s*(\w+)', text):
        if radix[1].upper() != 'HEX':
            sys.exit('%s: only HEX radix is supported (%s = %s)' % (src, radix[0], radix[1]))

    body = re.search(r'CONTENT\s+BEGIN(.*?)END\s*;', text, re.S | re.I).group(1)
    body = re.sub(r'--[^\n]*', '', body)
    mem = [0] * depth
    for stmt in body.split(';'):
        if ':' not in stmt:
            continue
        addr, vals = stmt.split(':', 1)
        vals = [int(v, 16) for v in vals.split()]
        addr = addr.strip()
        m = re.match(r'\[\s*([0-9A-Fa-f]+)\s*\.\.\s*([0-9A-Fa-f]+)\s*\]', addr)
        if m:
            lo, hi = int(m.group(1), 16), int(m.group(2), 16)
            for a in range(lo, hi + 1):
                mem[a] = vals[(a - lo) % len(vals)]
        else:
            base = int(addr, 16)
            for i, v in enumerate(vals):
                mem[base + i] = v

    digits = (width + 3) // 4
    with open(dst, 'w') as f:
        for v in mem:
            f.write('%0*x\n' % (digits, v))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
