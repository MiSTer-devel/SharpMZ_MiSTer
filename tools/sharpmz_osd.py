#!/usr/bin/env python3
"""The SharpMZ OSD options by name, read from SharpMZ.sv's CONF_STR.

The simulation (verilator/sim_headless.cpp --osd) reads the same CONF_STR, so a test can name options the same way on
the hardware (tools/mister_test.py) and in the sim:

    from sharpmz_osd import osd
    opts = osd('Fast Tape=Off, Tape Messages=On')      # -> [(21, 3, 1), (55, 1, 0)]: (low bit, width, value)

    python3 tools/sharpmz_osd.py                         # list the options, their status bits and values
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONF_SV = os.path.join(ROOT, 'SharpMZ.sv')

_table = None


def options(path=CONF_SV):
    """{name: (lo, width, [values])} for every O[...] entry, in CONF_STR order."""
    global _table
    if _table is not None and path == CONF_SV:
        return _table
    t = {}
    for line in open(path):
        m = re.search(r'"(?:P\d)?O\[(\d+)(?::(\d+))?\],([^;"]*);', line)
        if not m:
            continue
        hi = int(m.group(1))
        lo = int(m.group(2)) if m.group(2) else hi
        parts = m.group(3).split(',')
        t[parts[0]] = (lo, hi - lo + 1, parts[1:])
    if path == CONF_SV:
        _table = t
    return t


def _norm(s):
    return s.strip().lower()


def lookup(name, value):
    """(lo, width, index) for an option and one of its values (as the OSD shows them, or an index)."""
    t = options()
    key = next((k for k in t if _norm(k) == _norm(name)), None)
    if key is None:
        raise KeyError(f'no OSD option {name!r}; options: {", ".join(t)}')
    lo, width, values = t[key]
    v = next((i for i, x in enumerate(values) if _norm(x) == _norm(str(value))), None)
    if v is None and str(value).strip().isdigit():
        v = int(value)
    if v is None:
        raise KeyError(f'OSD option {key!r} has no value {value!r}; values: {", ".join(values)}')
    return lo, width, v


def osd(assignments):
    """'Name=Value, Name=Value' -> [(lo, width, value), ...]."""
    out = []
    for item in assignments.split(','):
        if not item.strip():
            continue
        name, _, value = item.partition('=')
        out.append(lookup(name, value))
    return out


if __name__ == '__main__':
    for name, (lo, width, values) in options(sys.argv[1] if len(sys.argv) > 1 else CONF_SV).items():
        bits = f'{lo}' if width == 1 else f'{lo + width - 1}:{lo}'
        print(f'{name:26s} [{bits:>7s}]  ' + ', '.join(f'{i}={v}' for i, v in enumerate(values)))
