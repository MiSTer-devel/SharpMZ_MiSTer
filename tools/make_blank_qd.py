#!/usr/bin/env python3
"""Create a blank Quick Disk image (.qdf) for the OSD Quick Disk slot.

Usage: make_blank_qd.py [OUT.qdf]   (default blank.qdf)

MiSTer can't grow a mounted image, so a disk to write on must be full size: the
16-byte "-QD format-" header of the dumps plus 81920 bytes of medium, all zero
(an unformatted disk). Format it on the machine (MZ-1500 BASIC: INIT "QD:").
"""
import sys

out = sys.argv[1] if len(sys.argv) > 1 else 'blank.qdf'
with open(out, 'wb') as f:
    f.write(b'-QD format-' + b'\xff' * 5 + bytes(81920))
print('%s: blank Quick Disk' % out)
