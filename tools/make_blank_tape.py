#!/usr/bin/env python3
"""Create a blank SharpMZ tape image for the OSD "Tape Image" slot.

Usage: make_blank_tape.py [OUT.mzt] [SIZE_KB]   (default blank.mzt, 1024 KB)

MiSTer can't grow a mounted image, so saves need spare room in the file. The
image is zero-filled: a zero attribute byte marks the end of the tape, and each
saved program is appended as an MZF record (128-byte header + data).
"""
import sys

out = sys.argv[1] if len(sys.argv) > 1 else 'blank.mzt'
kb = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
with open(out, 'wb') as f:
    f.write(bytes(kb * 1024))
print('%s: %d KB blank tape' % (out, kb))
