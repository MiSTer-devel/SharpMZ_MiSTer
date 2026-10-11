#!/usr/bin/env python3
"""Patch the combined keymap after romtool (build_meminitfiles.sh), and rewrite its MIF.

The keymap is 8 banks of 256 bytes, one per model, indexed by the PS/2 set 2 code with bit 7 set
for extended (E0) keys. Each byte is the MZ key matrix position: row in bits 7:4, column in 2:0;
FF means no key. In the MZ-80K/80C/1200/80A banks bit 3 also presses SHIFT (keymatrix.vhd).

1. MZ-700 and MZ-800 banks: the layout of mz800emu (src/iface/iface_keyboard.c), the reference for
   these machines. The old table had 4 on C, no Backspace/Delete/Insert/Home/End, no right SHIFT,
   CTRL on a row the machine doesn't have, and no : ' key.
2. MZ-80K/80C/1200/80A banks: the cursor keys, Backspace/Delete/Insert and Home/End go to the machine's
   own keys, with SHIFT where needed (bit 3 of an entry, see below). UP/DOWN, RIGHT/LEFT, INST/DEL and
   CLR/HOME are one key each; which way is shifted comes from the monitors' key tables (SA-1510 and
   SP-1002): unshifted RIGHT, DEL and HOME on all of them, UP on the MZ-80A but DOWN on the MZ-80K.
   MZ-80A/1200: the keypad keys 0, 1, 2, 4, 5, 7 and 8 go to its keypad (row F8 of the sharpmz.net
   matrix). The old tables had the cursor keys on keypad digits and Backspace on / (80A) or on G keys.
3. Every bank: an extended key with no entry of its own (cursor keys, Insert, Delete, keypad Enter
   and /, right CTRL) gets the entry of its non-extended twin. keymatrix.vhd used to drop the
   extended flag, so these keys only ever reached the twin's entry; this keeps them working now
   that the flag is used.

usage: fix_keymap.py ROMDIR MIFDIR
"""
import sys

romdir, mifdir = sys.argv[1], sys.argv[2]
BANK = {'MZ80K': 0, 'MZ80C': 1, 'MZ1200': 2, 'MZ80A': 3, 'MZ700': 4, 'MZ800': 5}
SHIFT = 0x08                    # MZ-80K/80C/1200/80A banks: also press SHIFT
EXT = 0x80


def k(row, col):
    return (row << 4) | col


# PS/2 code -> MZ-700 matrix (mz800emu, MZ-700 build).
MZ700 = {
    0x0E: k(0, 7),              # `      BLANK
    0x58: k(0, 6),              # Caps   GRAPH
    0x01: k(0, 5),              # F9     LIBRA (pound)
    0x5D: k(0, 4),              # \      ALPHA
    0x61: k(0, 4),              # ISO \  ALPHA
    0x0D: k(0, 4),              # Tab    ALPHA (the MZ-700 has no TAB key)
    0x4C: k(0, 2),              # ;
    0x52: k(0, 1),              # '      :
    0x5A: k(0, 0),              # Enter  CR
    EXT | 0x5A: k(0, 0),        # KP Enter
    0x35: k(1, 7), 0x1A: k(1, 6),                                   # Y Z
    0x0B: k(1, 5),              # F6     @
    0x54: k(1, 4),              # [
    0x5B: k(1, 3),              # ]
    0x15: k(2, 7), 0x2D: k(2, 6), 0x1B: k(2, 5), 0x2C: k(2, 4),     # Q R S T
    0x3C: k(2, 3), 0x2A: k(2, 2), 0x1D: k(2, 1), 0x22: k(2, 0),     # U V W X
    0x43: k(3, 7), 0x3B: k(3, 6), 0x42: k(3, 5), 0x4B: k(3, 4),     # I J K L
    0x3A: k(3, 3), 0x31: k(3, 2), 0x44: k(3, 1), 0x4D: k(3, 0),     # M N O P
    0x1C: k(4, 7), 0x32: k(4, 6), 0x21: k(4, 5), 0x23: k(4, 4),     # A B C D
    0x24: k(4, 3), 0x2B: k(4, 2), 0x34: k(4, 1), 0x33: k(4, 0),     # E F G H
    0x16: k(5, 7), 0x1E: k(5, 6), 0x26: k(5, 5), 0x25: k(5, 4),     # 1 2 3 4
    0x2E: k(5, 3), 0x36: k(5, 2), 0x3D: k(5, 1), 0x3E: k(5, 0),     # 5 6 7 8
    0x69: k(5, 7), 0x72: k(5, 6), 0x7A: k(5, 5), 0x6B: k(5, 4),     # keypad 1 2 3 4
    0x73: k(5, 3), 0x74: k(5, 2), 0x6C: k(5, 1), 0x75: k(5, 0),     # keypad 5 6 7 8
    0x55: k(6, 6),              # =      ^ (tilde in mz800emu)
    0x4E: k(6, 5),              # -
    0x7B: k(6, 5),              # KP -
    0x29: k(6, 4),              # Space
    0x45: k(6, 3), 0x70: k(6, 3),                                   # 0, keypad 0
    0x46: k(6, 2), 0x7D: k(6, 2),                                   # 9, keypad 9
    0x41: k(6, 1),              # ,
    0x49: k(6, 0), 0x71: k(6, 0),                                   # ., keypad .
    EXT | 0x70: k(7, 7),        # Insert INST
    EXT | 0x71: k(7, 6),        # Delete DEL
    0x66: k(7, 6),              # Backspace DEL
    EXT | 0x75: k(7, 5),        # Up
    EXT | 0x72: k(7, 4),        # Down
    EXT | 0x74: k(7, 3),        # Right
    EXT | 0x6B: k(7, 2),        # Left
    0x0A: k(7, 1),              # F8     ?
    0x4A: k(7, 0),              # /
    EXT | 0x4A: k(7, 0),        # KP /
    EXT | 0x69: k(8, 7),        # End    BREAK
    0x14: k(8, 6),              # Ctrl   CTRL
    EXT | 0x14: k(8, 6),        # right Ctrl
    0x12: k(8, 0),              # Shift
    0x59: k(8, 0),              # right Shift
}

# The MZ-800 has a TAB key; ALPHA stays on the backslash keys.
MZ800 = dict(MZ700)
MZ800[0x0D] = k(0, 3)

# MZ-80A (sharpmz.net mz80a/kbdmatrix: rows F0-F9; SHIFT is F0 bit 0).
MZ80A = {
    EXT | 0x75: k(7, 4),            # Up        UP/DOWN
    EXT | 0x72: k(7, 4) | SHIFT,    # Down      shift UP/DOWN
    EXT | 0x74: k(7, 5),            # Right     RIGHT/LEFT
    EXT | 0x6B: k(7, 5) | SHIFT,    # Left      shift RIGHT/LEFT
    0x66: k(1, 2),                  # Backspace INST/DEL
    EXT | 0x71: k(1, 2),            # Delete    INST/DEL
    EXT | 0x70: k(1, 2) | SHIFT,    # Insert    shift INST/DEL
    EXT | 0x6C: k(7, 7),            # Home      CLR/HOME
    EXT | 0x69: k(7, 7) | SHIFT,    # End       shift CLR/HOME (CLR)
    0x70: k(8, 0),                  # KP 0
    0x69: k(8, 2),                  # KP 1
    0x72: k(8, 3),                  # KP 2
    0x6B: k(8, 4),                  # KP 4
    0x73: k(8, 5),                  # KP 5
    0x6C: k(8, 6),                  # KP 7
    0x75: k(8, 7),                  # KP 8
    0x14: k(0, 7),                  # Ctrl      CTL (was F2 bit 7, the 4 key)
    EXT | 0x14: k(0, 7),            # right Ctrl
    0x76: k(0, 7) | SHIFT,          # Esc       BREAK (shift CTL)
    0x59: k(0, 0),                  # right Shift SHIFT (was F0 bit 7, CTL)
    0x11: k(0, 1),                  # Alt       GRPH
    EXT | 0x11: k(0, 1),            # right Alt
}

# MZ-80K / 80C (sharpmz.net mz80k/kbdmatrix: LSHIFT F8 bit 0; SP-1002's table: unshifted DOWN, RIGHT, DEL, HOME).
MZ80K = {
    EXT | 0x75: k(9, 2) | SHIFT,    # Up        shift UP/DOWN
    EXT | 0x72: k(9, 2),            # Down      UP/DOWN
    EXT | 0x74: k(8, 3),            # Right     RIGHT/LEFT
    EXT | 0x6B: k(8, 3) | SHIFT,    # Left      shift RIGHT/LEFT
    0x66: k(8, 1),                  # Backspace INST/DEL
    EXT | 0x71: k(8, 1),            # Delete    INST/DEL
    EXT | 0x70: k(8, 1) | SHIFT,    # Insert    shift INST/DEL
    EXT | 0x6C: k(9, 0),            # Home      CLR/HOME
    EXT | 0x69: k(9, 0) | SHIFT,    # End       shift CLR/HOME (CLR)
}

# Extended keys and their non-extended twins, for the other banks.
TWINS = [0x69, 0x6B, 0x6C, 0x70, 0x71, 0x72, 0x74, 0x75, 0x7A, 0x7D, 0x4A, 0x5A, 0x14, 0x11]

rom = bytearray(open(f"{romdir}/combined_keymap.rom", "rb").read())
for model, table in (('MZ80K', MZ80K), ('MZ80C', MZ80K), ('MZ1200', MZ80A), ('MZ80A', MZ80A), ('MZ700', MZ700), ('MZ800', MZ800)):
    base = BANK[model] * 256
    for code, val in table.items():
        rom[base + code] = val
# The keyboard's AA (self test passed) reads entry EF; banks 0-3 had EF there, which is bit 3 (SHIFT) now.
for bank in range(4):
    rom[bank * 256 + 0xEF] = 0xFF
for bank in range(8):
    base = bank * 256
    for c in TWINS:
        if rom[base + EXT + c] == 0xFF and rom[base + c] != 0xFF:
            rom[base + EXT + c] = rom[base + c]

open(f"{romdir}/combined_keymap.rom", "wb").write(rom)
with open(f"{mifdir}/combined_keymap.mif", "w") as f:
    f.write(f"DEPTH = {len(rom)};\nWIDTH = 8;\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\nCONTENT BEGIN\n")
    for a in range(0, len(rom), 16):
        f.write(f"{a:04x}: " + " ".join(f"{b:02x}" for b in rom[a:a + 16]) + ";\n")
    f.write("END;\n")
