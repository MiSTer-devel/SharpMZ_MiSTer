#!/usr/bin/env python3
"""Make tests/printer/prntest.mzf: print a text line through the Sharp printer handshake. Also prnsharp.mzf: lowercase
in Sharp codes and bare CRs (as BASIC PRINT/P sends them), for the OSD Printer Charset: ASCII conversion.

Runs on the MZ-700 (printer port FE/FF) and the MZ-800/1500 (Z80 PIO: port A bit mode with PA6/PA7 out, port B
output; the PIO set-up writes go to FC/FD, unused on the MZ-700). For each byte: wait for RDA (FE bit 0) low,
OUT FF byte, OUT FE 80h (RDP), wait for RDA high, OUT FE 0. Loaded and started at 2000h.
"""
import os
ORG = 0x2000
MSG = b"HELLO FROM THE SHARP MZ\r\n0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n\x0c"

def sharp(text):
    """ASCII -> Sharp ASCII with the core's own table (the second half of ascii_conv.mif)."""
    mif = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../rtl/software/mif/ascii_conv.mif')
    t = {}
    for line in open(mif):
        if ':' in line and line.strip()[:1] in '0123456789abcdefABCDEF':
            a, _, d = line.partition(':')
            for i, v in enumerate(d.strip().rstrip(';').split()):
                t[int(a, 16) + i] = int(v, 16)
    return bytes(t[0x100 + c] if 0x20 <= c < 0x80 else c for c in text)


def build(MSG=MSG):
    c = bytearray()
    c += bytes([0x3E, 0xCF, 0xD3, 0xFC])         # PIO A: bit mode
    c += bytes([0x3E, 0x3F, 0xD3, 0xFC])         #        bits 0-5 in, 6-7 out
    c += bytes([0x3E, 0x0F, 0xD3, 0xFD])         # PIO B: output
    c += bytes([0xAF, 0xD3, 0xFE])               # RDP low
    msg_ref = len(c) + 1
    c += bytes([0x21, 0, 0])                     # LD HL,msg
    loop = len(c)
    c += bytes([0x7E, 0xB7, 0x28, 0])            # LD A,(HL); OR A; JR Z,done
    jz = len(c) - 1
    c += bytes([0x4F])                           # LD C,A
    c += bytes([0xDB, 0xFE, 0xE6, 0x01, 0x20, 0xFA])   # wait RDA low
    c += bytes([0x79, 0xD3, 0xFF])               # OUT (FF),C
    c += bytes([0x3E, 0x80, 0xD3, 0xFE])         # RDP high
    c += bytes([0xDB, 0xFE, 0xE6, 0x01, 0x28, 0xFA])   # wait RDA high (acknowledge)
    c += bytes([0xAF, 0xD3, 0xFE])               # RDP low
    c += bytes([0x23, 0x18, 0])                  # INC HL; JR loop
    c[-1] = (loop - len(c)) & 0xFF
    done = len(c)
    c += bytes([0x18, 0xFE])                     # JR $
    c[jz] = (done - (jz + 1)) & 0xFF
    msg = ORG + len(c)
    c[msg_ref:msg_ref + 2] = msg.to_bytes(2, 'little')
    c += MSG + b"\0"
    return bytes(c)

for fname, title, msg in (('prntest.mzf', b"PRNTEST", MSG),
                          ('prnsharp.mzf', b"PRNSHARP", sharp(b"Hello sharp mz\r") + sharp(b"abcdefghijklmnopqrstuvwxyz\r"))):
    code = build(msg)
    hdr = bytearray(128); hdr[0] = 1
    name = title + b"\r"; hdr[1:1 + len(name)] = name
    hdr[18:20] = len(code).to_bytes(2, 'little'); hdr[20:22] = ORG.to_bytes(2, 'little'); hdr[22:24] = ORG.to_bytes(2, 'little')
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), fname)
    open(out, 'wb').write(bytes(hdr) + code)
    print(out, len(code))
