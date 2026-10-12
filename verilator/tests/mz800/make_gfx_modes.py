#!/usr/bin/env python3
"""Write MZ-800 graphics mode tests (load/exec 2000h). Each sets a display mode (DMD), the palette,
and fills planes through the write format register (WF) with address-dependent patterns, so the
VRAM address mapping, pixel order and colour mapping all show up in the picture.

  gfx640.mzf    DMD=04  640x200, 2 colours (plane I)
  gfx640h.mzf   DMD=06  640x200, 4 colours (planes I, III; MZ-1R25)
  gfx320h.mzf   DMD=02  320x200, 16 colours (planes I-IV; MZ-1R25)
  gfx320b.mzf   DMD=01  320x200, 4 colours, frame B (planes III, IV; MZ-1R25)
  gfx320x.mzf   DMD=00  320x200, 4 colours, frame A (planes I, II), XOR patterns
  gfxwm.mzf     DMD=02  fill all planes, then EXOR / OR / RESET / REPLACE / PSET on 40-line bands
  gfxwm640.mzf  DMD=06  the same write modes at 640x200, 4 colours
  gfxrw.mzf     DMD=00  RF reads: copy plane II to plane I, and a colour search into plane II
  gfxrw16.mzf   DMD=02  16 colours: colour searches with the RF frame bit 0 and 1 (the display mode decides, as in
                        mz800emu; Abu Simbel clears VRAM this way with RF=8C)
  gfxscr.mzf    DMD=00  full screen hardware scroll (SOF 8 lines), then CPU writes into the scrolled VRAM
  gfxscr640.mzf DMD=06  hardware scroll of a window (SSA/SEA/SW) by 3 lines at 640x200
  gfxscr640b.mzf DMD=06 full screen scroll with a large offset (SOF 3C0, needs SOF2) and writes before and after
"""

# Patterns: 2 bytes computing A from HL (the VRAM address).
PAT = {
    'hxl': [0x7C, 0xAD],   # LD A,H; XOR L
    'l':   [0x7D, 0x00],   # LD A,L; NOP
    'hr':  [0x7C, 0x0F],   # LD A,H; RRCA
    'nl':  [0x7D, 0x2F],   # LD A,L; CPL
}


def program(dmd, planes, count):
    c = [0xF3, 0x3E, dmd, 0xD3, 0xCE, 0xDB, 0xE0]          # DI; OUT (CE),dmd; IN A,(E0)
    for i, col in enumerate((0x1, 0xE, 0xC, 0xF)):          # palette 0-3: blue, yellow, light green, white
        c += [0x3E, (i << 4) | col, 0xD3, 0xF0]
    for wf, pat in planes:
        c += [0x3E, wf, 0xD3, 0xCC,                         # WF: single write, these planes
              0x21, 0x00, 0x80,                             # LD HL,8000
              0x01, count & 0xFF, count >> 8]               # LD BC,count
        c += PAT[pat] + [0x77, 0x23, 0x0B, 0x78, 0xB1, 0x20, 0xF7]
    c += [0x18, 0xFE]                                       # JR $
    return bytes(c)


def header(dmd):
    c = [0xF3, 0x3E, dmd, 0xD3, 0xCE, 0xDB, 0xE0]
    for i, col in enumerate((0x1, 0xE, 0xC, 0xF)):
        c += [0x3E, (i << 4) | col, 0xD3, 0xF0]
    return c


def fill(wf, pat, start, count):
    """WF=wf, then write pattern pat to start..start+count-1."""
    return [0x3E, wf, 0xD3, 0xCC, 0x21, start & 0xFF, start >> 8, 0x01, count & 0xFF, count >> 8] \
        + PAT[pat] + [0x77, 0x23, 0x0B, 0x78, 0xB1, 0x20, 0xF7]


def copy(rf, wf, src, dst, count):
    """RF=rf, WF=wf, then copy count bytes src -> dst through the CPU."""
    return [0x3E, rf, 0xD3, 0xCD, 0x3E, wf, 0xD3, 0xCC,
            0x21, src & 0xFF, src >> 8, 0x11, dst & 0xFF, dst >> 8, 0x01, count & 0xFF, count >> 8,
            0x7E, 0x12, 0x23, 0x13, 0x0B, 0x78, 0xB1, 0x20, 0xF7]


def write_modes(dmd, line, planes):
    """Fill the given planes, then one write mode per 40-line band. line = bytes per line."""
    c = header(dmd)
    for wf, pat in planes:
        c += fill(wf, pat, 0x8000, line * 200)
    band = line * 40
    c += fill(0x2F, 'nl',  0x8000 + 0 * band, band)   # EXOR, all planes
    c += fill(0x43, 'hr',  0x8000 + 1 * band, band)   # OR, planes I, II
    c += fill(0x6C, 'l',   0x8000 + 2 * band, band)   # RESET, planes III, IV
    c += fill(0x85, 'hxl', 0x8000 + 3 * band, band)   # REPLACE, planes I, III
    c += fill(0xCA, 'nl',  0x8000 + 4 * band, band)   # PSET, planes II, IV
    return bytes(c + [0x18, 0xFE])


def mzf(name, code, addr=0x2000):
    hdr = bytes([1]) + name.upper().encode().ljust(16, b'\r')[:16] + b'\r' + len(code).to_bytes(2, 'little') \
        + addr.to_bytes(2, 'little') + addr.to_bytes(2, 'little')
    open(f'{name}.mzf', 'wb').write(hdr.ljust(128, b'\0') + code)


mzf('gfx640',  program(0x04, [(0x01, 'hxl')], 16000))
mzf('gfx640h', program(0x06, [(0x01, 'hxl'), (0x04, 'l')], 16000))
mzf('gfx320h', program(0x02, [(0x01, 'hxl'), (0x02, 'l'), (0x04, 'hr'), (0x08, 'nl')], 8000))
mzf('gfx320b', program(0x01, [(0x04, 'hxl'), (0x08, 'l')], 8000))
mzf('gfx320x', program(0x00, [(0x01, 'hxl'), (0x02, 'l')], 8000))

mzf('gfxwm',    write_modes(0x02, 40, [(0x01, 'hxl'), (0x02, 'l'), (0x04, 'hr'), (0x08, 'nl')]))
mzf('gfxwm640', write_modes(0x06, 80, [(0x01, 'hxl'), (0x04, 'l')]))
rw = header(0x00) + fill(0x01, 'hxl', 0x8000, 8000) + fill(0x02, 'l', 0x8000, 8000)
rw += copy(0x02, 0x01, 0x8000, 0x8000 + 150 * 40, 50 * 40)      # plane II rows 0-49 -> plane I rows 150-199
rw += copy(0x83, 0x02, 0x8000, 0x8000 + 100 * 40, 50 * 40)      # search colour 3 in rows 0-49 -> plane II rows 100-149
mzf('gfxrw', bytes(rw + [0x18, 0xFE]))
rw16 = header(0x02) + fill(0x01, 'hxl', 0x8000, 8000) + fill(0x02, 'l', 0x8000, 8000) \
    + fill(0x04, 'hr', 0x8000, 8000) + fill(0x08, 'nl', 0x8000, 8000)
rw16 += copy(0x8C, 0x01, 0x8000, 0x8000 + 100 * 40, 50 * 40)   # search colour C (frame bit 0) -> plane I rows 100-149
rw16 += copy(0x93, 0x02, 0x8000, 0x8000 + 150 * 40, 50 * 40)   # search colour 3 (frame bit 1) -> plane II rows 150-199
mzf('gfxrw16', bytes(rw16 + [0x18, 0xFE]))


def crtc(regs):
    """OUT (C),A to port CF with B = register (1 SOF lo, 2 SOF hi, 3 SW, 4 SSA, 5 SEA)."""
    c = []
    for reg, val in regs:
        c += [0x01, 0xCF, reg, 0x3E, val, 0xED, 0x79]
    return c


scr = header(0x00) + fill(0x01, 'hxl', 0x8000, 8000) + fill(0x02, 'l', 0x8000, 8000)
scr += crtc([(1, 40), (2, 0), (3, 0x7D), (4, 0x00), (5, 0x7D)])
scr += fill(0x03, 'nl', 0x8000, 400)                          # 10 lines through the scrolled addressing
mzf('gfxscr', bytes(scr + [0x18, 0xFE]))
scr = header(0x06) + fill(0x01, 'hxl', 0x8000, 16000) + fill(0x04, 'l', 0x8000, 16000)
scr += crtc([(1, 15), (2, 0), (3, 0x50), (4, 0x14), (5, 0x64)])
mzf('gfxscr640', bytes(scr + [0x18, 0xFE]))

scr = header(0x06) + fill(0x01, 'hxl', 0x8000, 16000)
scr += crtc([(1, 0xC0), (2, 0x03), (3, 0x7D), (4, 0x00), (5, 0x7D)])
scr += fill(0x04, 'l', 0x8000, 16000)                          # plane III through the scrolled addressing
mzf('gfxscr640b', bytes(scr + [0x18, 0xFE]))
