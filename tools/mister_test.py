#!/usr/bin/env python3
"""Hardware test suite for the SharpMZ core on a MiSTer.

Each test is an MGL that loads the core with its own <setname>, so it gets its own config file
(<setname>_v5.CFG) holding the OSD settings (model etc.). The MGL mounts the tape/disk images
and resets; this script then types keys through a uinput keyboard (tools/mister_keys.py on the SD card) and takes
screenshots with Main's `screenshot` command, then copies them back.

Needs: root ssh to the MiSTer (python3 and /dev/uinput there: tools/mister_keys.py is copied to /tmp and run as a
virtual keyboard; it is kept on the SD card at /media/fat/tools/mister_keys.py). The software comes from the
repository's gitignored folders (software/, verilator test programs) and is copied to
games/SharpMZ/HWTest on the MiSTer; disk images are copied fresh for each run because the core
writes back to them.

usage: mister_test.py [--host mister.local] [--rbf output_files/SharpMZ.rbf] [--only T03,T08]
                      [--out out/mister] [--no-deploy]
"""
import argparse, datetime, hashlib, json, os, shutil, socket, subprocess, sys, time, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sharpmz_osd import osd                   # OSD options by name, from SharpMZ.sv's CONF_STR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SW = os.path.join(ROOT, 'software')
GAMES800 = os.path.join(SW, 'MZ-800-full/MZ-800/MZ-800 Software/COM/MZF/Games/800')
DSK = os.path.join(SW, 'dsk')
RB = os.path.join(SW, 'idealine/mz-80b/rb_DSK/DSK')
TESTS = os.path.join(ROOT, 'verilator/tests/mz800')
MZF = os.path.join(ROOT, 'rtl/software/mzf')
FAT = '/media/fat'
HW = f'{FAT}/games/SharpMZ/HWTest'
CFG_VER = '_v5'           # CONF_STR "v,5"

# Model menu entries (status[38:35]), in CONF_STR order.
MODEL = {'MZ80A': 0, 'MZ80K': 1, 'MZ80C': 2, 'MZ1200': 3, 'MZ700': 4, 'MZ80B': 5, 'MZ2000': 6, 'MZ800': 7, 'MZ1500': 8}


# The tests' baseline, where it differs from the core's defaults: Keyboard Layout Sharp (KEYS below types by position),
# Fast Tape Off (the waits were made at real speed), Tape Messages Off (the overlay would change screenshots).
BASELINE = 'Keyboard Layout=Sharp, Fast Tape=Off, Tape Messages=Off'


def status_bytes(model, opts=()):
    """16-byte CFG: status bit n is byte n/8, bit n%8. opts: (low_bit, width, value) from osd('Name=Value, ...')."""
    st = 0
    for lo, width, val in osd(f'Model={MODEL[model]}, ' + BASELINE) + list(opts):
        st = st & ~(((1 << width) - 1) << lo) | (val & ((1 << width) - 1)) << lo
    return st.to_bytes(16, 'little')


FAST_TAPE = lambda step: (21, 3, step)     # OSD Fast Tape: 0 Fastest, 1 Off, 2 2x .. 5 16x, 6 Fastest (was 32x)
PC_KEYS = osd('Keyboard Layout=PC')[0]      # (the tests default to Sharp)
MZ800_MODE = osd('MZ-800 Mode=MZ-800')[0]   # rear switch in the MZ-800 position

# A test: name, model, OSD options, files to mount [(kind, index, local source)], reset after
# mounting, then steps: ('wait', s) / ('type', text) / ('shot', label).
# kind: 's' = image slot (S0 tape, S1/S2 floppy), 'f' = file load (F1 tape to CMT, F2 direct).
T = []
def test(name, model, desc, files=(), opts=(), reset=False, steps=(), late=()):
    # late: [(kind, index, source, delay)] mounted by the MGL after the reset, e.g. a disk's side B.
    T.append(dict(name=name, model=model, desc=desc, files=list(files), opts=list(opts), reset=reset, steps=list(steps), late=list(late)))

test('T01', 'MZ80K', 'MZ-80K boots to the SP-1002 monitor', steps=[('wait', 4), ('shot', 'boot')])
test('T02', 'MZ80A', 'MZ-80A boots to the SA-1510 monitor', steps=[('wait', 4), ('shot', 'boot')])
test('T03', 'MZ700', 'MZ-700 boots to the 1Z-013A monitor', steps=[('wait', 4), ('shot', 'boot')])
test('T04', 'MZ800', 'MZ-800 IPL menu', steps=[('wait', 4), ('shot', 'boot')])
test('T05', 'MZ80B', 'MZ-80B IPL (no disk: asks for the tape)', steps=[('wait', 6), ('shot', 'boot')])
test('T06', 'MZ2000', 'MZ-2000 IPL: "IPL is looking for a program"', steps=[('wait', 6), ('shot', 'boot')])
test('T07', 'MZ700', 'MZ-700 tape: L loads ramtest from the tape image', files=[('s', 0, f'{MZF}/ramtest.mzf')],
     steps=[('wait', 2), ('type', 'L\n'), ('wait', 20), ('shot', 'loaded')])
test('T08', 'MZ700', 'MZ-700 floppy: J F000 boots a disk (MZ-1E05 ROM)', files=[('s', 1, 'gen:fd700')], reset=True,
     steps=[('wait', 3), ('type', 'JF000\n'), ('wait', 12), ('shot', 'booted')])
test('T09', 'MZ800', 'MZ-800 graphics 640x200 test program (direct load, M, J2000)', files=[('f', 2, f'{TESTS}/gfx640.mzf')],
     steps=[('wait', 2), ('type', 'M'), ('wait', 2), ('type', 'J2000\n'), ('wait', 6), ('shot', 'gfx640')])
test('T10', 'MZ800', 'MZ-800 graphics 320x200 16 colours (direct load, M, J2000)', files=[('f', 2, f'{TESTS}/gfx320h.mzf')],
     steps=[('wait', 2), ('type', 'M'), ('wait', 2), ('type', 'J2000\n'), ('wait', 6), ('shot', 'gfx320h')])
test('T11', 'MZ800', 'MZ-800 IPL loads Cauldron II from a tape image (C)', files=[('s', 0, f'{GAMES800}/Cauldron.mzf')],
     opts=[FAST_TAPE(5)], steps=[('wait', 10), ('type', 'C'), ('wait', 45), ('shot', '45s'), ('wait', 30), ('shot', '75s')])
test('T12', 'MZ800', 'MZ-800 IPL loads Cybernoid from a tape image (C)', files=[('s', 0, f'{GAMES800}/Cyberno.mzf')],
     opts=[FAST_TAPE(5)], steps=[('wait', 10), ('type', 'C'), ('wait', 45), ('shot', '45s'), ('wait', 30), ('shot', '75s')])
test('T13', 'MZ800', 'MZ-800 CP/M 4.1 boots from floppy; DIR', files=[('s', 1, f'{DSK}/CPMv41 System.dsk')], reset=True,
     steps=[('wait', 15), ('shot', 'boot'), ('type', 'DIR\n'), ('wait', 4), ('shot', 'dir')])
test('T14', 'MZ800', 'MZ-800 CP/M 1.3 boots from floppy', files=[('s', 1, f'{DSK}/CPMv13A System.dsk')], reset=True,
     steps=[('wait', 20), ('shot', 'boot')])
test('T15', 'MZ800', 'MZ-800 CPMv41 Hry COM A: file manager autostarts', files=[('s', 1, f'{DSK}/CPMv41 Hry COM A.dsk')], reset=True,
     steps=[('wait', 20), ('shot', 'boot')])
test('T16', 'MZ80B', 'MZ-80B floppy: SB-6511 Disk BASIC (DISK23)', files=[('s', 1, f'{RB}/DISK23.DSK')], reset=True,
     steps=[('wait', 20), ('shot', 'boot')])
test('T17', 'MZ80B', 'MZ-80B floppy: CP/M 2.2 (DISK01)', files=[('s', 1, f'{RB}/DISK01.DSK')], reset=True,
     steps=[('wait', 25), ('shot', 'boot')])
test('T18', 'MZ2000', 'MZ-2000 floppy: MZ-80B CP/M 2.2 (black screen in the sim)', files=[('s', 1, f'{RB}/DISK01.DSK')], reset=True,
     steps=[('wait', 25), ('shot', 'boot')])
test('T19', 'MZ700', 'MZ-700 sound: BELL (880 Hz) then a steady 440 Hz A (listen)', files=[('f', 2, f'{ROOT}/verilator/tests/sound/beep700.mzf')],
     steps=[('wait', 2), ('type', 'J2000\n'), ('wait', 3), ('shot', 'beep')])
test('T20', 'MZ800', 'MZ-800 sound: the same BELL and 440 Hz A through the 8253 (listen)', files=[('f', 2, f'{ROOT}/verilator/tests/sound/beep700.mzf')],
     steps=[('wait', 2), ('type', 'M'), ('wait', 2), ('type', 'J2000\n'), ('wait', 3), ('shot', 'beep')])
test('T21', 'MZ80B', 'MZ-80B tape: the IPL loads SB-5520 BASIC from a tape image', files=[('s', 0, f'{SW}/mz80b/SB-5520.mzt')],
     opts=[FAST_TAPE(5)], reset=True, steps=[('wait', 40), ('shot', 'basic')])
test('T22', 'MZ2000', 'MZ-2000 tape: the IPL loads Gang Man (Hudson Soft)', files=[('s', 0, f'{SW}/mz2200/Gang Man (1983)(Hudson Soft)(Fumihiko Itagaki) [CT].mzt')],
     opts=[FAST_TAPE(5)], reset=True, steps=[('wait', 40), ('shot', 'title')])
test('T23', 'MZ2000', 'MZ-2000 floppy: TF-DOS boot disk (fukui brave.d88)', files=[('s', 1, f'{SW}/fukui-mz2000/brave.d88')], reset=True,
     steps=[('wait', 25), ('shot', 'boot')])
test('T24', 'MZ2000', 'MZ-2000 tape: Zero Fighter (Hudson Soft), colour title screen', files=[('s', 0, f'{SW}/mz2200/Zero Fighter (1983)(Hudosn Soft) [CT].mzt')],
     opts=[FAST_TAPE(5)], reset=True, steps=[('wait', 40), ('shot', 'title')])
test('T25', 'MZ1500', 'MZ-1500 IPL menu ("Make ready QD", F/Q/C/M)', steps=[('wait', 5), ('shot', 'boot')])
test('T26', 'MZ1500', 'MZ-1500 Quick Disk: Lode Runner (Q), PCG title screen', files=[('s', 3, f'{SW}/mz1500/Lode Runner (1985)(Broderbund Software)(Universe) Side A.qdf')],
     reset=True, steps=[('wait', 4), ('type', 'Q'), ('wait', 25), ('shot', 'title')])

# MZ-1500 software: Quick Disk images (Q) and tapes (tape image + C at the IPL), two screenshots each.
M15 = f'{SW}/mz1500'
for n, (title, f) in enumerate([
        ('Battle City', 'Battle City (1986)(Dempa Shimbunsha)(Namco)(Masami Nakamura)(Manami Kadowaki)(Tamo Matsui)(Sei Kimigaki)(Miku) Side A.qdf'),
        ('Grobda', 'Grobda (1986)(Dempa Shimbunsha)(Namco)(Masami Nakamura)(Miku)(Manami Kadowaki)(Tamo Matsui)(Tadashi Fujioka) Side A.qdf'),
        ('Milky Way', 'Milky Way (1984)(Micronet)(Yasuro Koideya) Side A.qdf'),
        ('Nintendo Tennis', 'Nintendo Tennis (1985)(Hudson Soft)(Nintendo)(Masaaki Kikuta).qdf'),
        ('Batten Tanuki', 'Batten Tanuki No Daibouken (1986)(Tecno Soft) Side A.qdf')]):
    test(f'Q{n + 1:02d}', 'MZ1500', f'MZ-1500 Quick Disk: {title}', files=[('s', 3, f'{M15}/{f}')], reset=True,
         steps=[('wait', 4), ('type', 'Q'), ('wait', 25), ('shot', 'a'), ('wait', 20), ('shot', 'b')])
for n, (title, f) in enumerate([
        ('Pac-Man', 'Pac-Man (1984)(Dempa Shimbunsha)(Namco)(Noboru Gankou).mzt'),
        ('Mappy', 'Mappy (1984)(Dempa Shimbunsha)(Namco)(Game Roman)(Masami Nakamura) Side A.mzt'),
        ('Dig Dug', 'Dig Dug (1984)(Dempa Shimbunsha)(Game Roman)(Masami Nakamura) Side A.mzt'),
        ('Rally-X', 'Rally-X (1985)(Dempa Shimbunsha)(Namco)(Game Roman)(Masami Nakamura) Side A.mzt'),
        ('Mario Bros. Special', 'Mario Bros. Special (1984)(Hudson Soft).MZT'),
        ('Thunder Force', 'Thunder Force (1984)(Tecno Soft).mzt'),
        ('Door Door MkII', 'Door Door MkII (1984)(Enix)(Koichi Nakamura)(Side A).MZT'),
        ('Flappy', 'Flappy (1984)(DB-Soft)(Akira Obata) Side A.mzt'),
        ('Star Fighter', 'Star Fighter (1986)(Takeshi Maruyama).mzt'),
        ('Xetter91', 'Xetter91 (1991)(Mushakun).mzt'),
        ('Druaga no Tou', 'Druaga no Tou (1984)(Dempa Shimbunsha)(Namco)(Masami Nakamura) Side A.mzt'),
        ('Galaga', 'Galaga (1985)(Dempa Shimbunsha)(Namco).MZT')]):
    test(f'C{n + 1:02d}', 'MZ1500', f'MZ-1500 tape: {title}', files=[('s', 0, f'{M15}/{f}')], opts=[FAST_TAPE(6)], reset=True,
         steps=[('wait', 6), ('type', 'C'), ('wait', 5), ('type', 'C'), ('wait', 35), ('shot', 'a'), ('wait', 20), ('shot', 'b')])

# Two-sided Quick Disks: side A loads, the game asks for side B; the MGL swaps the image, the test presses Return.
for n, (title, fa) in enumerate([
        ('Battle City', 'Battle City (1986)(Dempa Shimbunsha)(Namco)(Masami Nakamura)(Manami Kadowaki)(Tamo Matsui)(Sei Kimigaki)(Miku) Side A.qdf'),
        ('Grobda', 'Grobda (1986)(Dempa Shimbunsha)(Namco)(Masami Nakamura)(Miku)(Manami Kadowaki)(Tamo Matsui)(Tadashi Fujioka) Side A.qdf'),
        ('Milky Way', 'Milky Way (1984)(Micronet)(Yasuro Koideya) Side A.qdf'),
        ('Batten Tanuki', 'Batten Tanuki No Daibouken (1986)(Tecno Soft) Side A.qdf')]):
    test(f'B{n + 1:02d}', 'MZ1500', f'MZ-1500 Quick Disk: {title}, side A then side B',
         files=[('s', 3, f'{M15}/{fa}')], late=[('s', 3, f'{M15}/{fa.replace("Side A", "Side B")}', 35)], reset=True,
         steps=[('wait', 4), ('type', 'Q'), ('wait', 40), ('type', '\n'), ('wait', 30), ('shot', 'a'), ('wait', 20), ('shot', 'b')])

# Quick Disk writes: MZ-1500 BASIC (MZ-5Z001) on a Quick Disk made by tools/mzf2qdf.py boots with Q, formats the
# disk (INIT "QD:"), saves a program, loads it back and runs it. The image is fetched and its blocks checked.
test('W01', 'MZ1500', 'MZ-1500 Quick Disk write: BASIC INIT, SAVE, LOAD', files=[('s', 3, 'gen:qd_basic')], reset=True,
     steps=[('wait', 4), ('type', 'Q'), ('wait', 20), ('shot', 'ready'), ('type', 'INIT "QD:"\n'), ('wait', 3), ('shot', 'init'),
            ('type', 'Y'), ('wait', 15), ('shot', 'formatted'), ('type', '10 PRINT 4321\n'), ('type', 'SAVE "TEST"\n'), ('wait', 15),
            ('shot', 'saved'), ('type', 'NEW\n'), ('type', 'LOAD "TEST"\n'), ('wait', 12), ('type', 'LIST\n'), ('type', 'RUN\n'),
            ('wait', 3), ('shot', 'loaded'), ('fetch', 0)])

# A tape installer: Druaga no Tou loads its DATA file from tape and copies the game onto a blank Quick Disk.
test('W02', 'MZ1500', 'MZ-1500 tape installer onto a blank Quick Disk: Druaga no Tou',
     files=[('s', 0, f'{M15}/Druaga no Tou (1984)(Dempa Shimbunsha)(Namco)(Masami Nakamura) Side A.mzt'), ('s', 3, 'gen:qd_blank')],
     opts=[FAST_TAPE(6)], reset=True,
     steps=[('wait', 8), ('shot', 'menu'), ('type', 'C'), ('wait', 5), ('type', 'C'), ('wait', 10), ('shot', 'loading'),
            ('wait', 60), ('shot', 'prompt'), ('type', '\n'), ('wait', 20),
            ('shot', 'a'), ('wait', 30), ('shot', 'b'), ('fetch', 1)])

HOLY = next((f for f in os.listdir(M15) if f.startswith('Holy Knight') and 'Side A' in f), 'Holy Knight') if os.path.isdir(M15) else ''

# Quick Disk titles sold or archived as tapes (side A: a DATA loader that asks for side B; side B: the game):
# tools/mzf2qdf.py turns each side into a Quick Disk, then they run like B01-B04. The Dempa/Game Roman loaders ask
# "SET PROGRAM QD ?" and want Y; the others take Return.
for n, (title, fa, fb, key) in enumerate([
        ('Druaga no Tou', 'Druaga no Tou (1984)(Dempa Shimbunsha)(Namco)(Masami Nakamura) Side A.mzt', None, '\n'),
        ('Rally-X', 'Rally-X (1985)(Dempa Shimbunsha)(Namco)(Game Roman)(Masami Nakamura) Side A.mzt', None, 'Y'),
        ('Dig Dug', 'Dig Dug (1984)(Dempa Shimbunsha)(Game Roman)(Masami Nakamura) Side A.mzt', None, 'Y'),
        ('Mappy', 'Mappy (1984)(Dempa Shimbunsha)(Namco)(Game Roman)(Masami Nakamura) Side A.mzt', None, 'Y'),
        ('Door Door MkII', 'Door Door MkII (1984)(Enix)(Koichi Nakamura)(Side A).MZT', None, '\n'),
        ('Knither', 'Knither - Demon Crystal 2 (1986)(YMCAT)(Dempa Shimbunsha)(Masami Nakamura)(Side A).MZT', None, '\n'),
        ('Zolvass', 'Zolvass (1986)(Takeshi Maruyama)(Side A).mzt', None, '\n'),
        ('Burnin\' Rubber', 'Burnin\' Rubber (1985)(Dempa Shimbunsha)(Data East)(Masami Nakamura) Side A.mzt',
         'Burnin\' Rubber (1985)(Dempa Shimbunshha)(Data East)(Masami Nakamura) Side B.mzt', 'Y'),
        ('Galaga', 'Galaga (1985)(Dempa Shimbunsha)(Namco).MZT', '-', '\n'),
        ('Dark Storm', 'Dark Storm - Demon Crystal 3 (1987)(YMCAT)(Dempa Shimbunsha)(Masami Nakamura)(Yasunobu Matsui) Side A.mzt', None, 'Y'),
        ('Demon Crystal', 'Demon Crystal (1984)(Dempa Shimbunsha)(Game Roman)(Yasunobu Matsui) Side A.mzt', None, 'Y'),
        ('Devil Land', 'Devil Land (1985)(YMCAT)(Game Roman)(Y. Morinaka)(T. Aochi) Side A.mzt', None, 'Y'),
        ('Feizer-21', 'Feizer-21 (1984)(Game Roman)(Side A).mzt', None, 'Y'),
        ('Flappy', 'Flappy (1984)(DB-Soft)(Akira Obata) Side A.mzt', None, '\n'),
        ('Holy Knight', HOLY, None, 'Y'),
        ('Volgurd', 'Volgurd (1984)(db-Soft)(Side A).mzt', None, 'Y'),
        ('Nonbarla Panic', 'Nonbarla Panic (1985)(Compac)(Shinsuke Nakamura).mzt', '-', '\n'),
        ('Youkai Toubatsu Hidejirou', 'Youkai Toubatsu Hidejirou (1987)(Takeshi Maruyama) Side A.mzt', None, ' ')]):
    fb = fb or fa.replace('Side A', 'Side B').replace('(Side A)', '(Side B)')
    test(f'G{n + 1:02d}', 'MZ1500', f'MZ-1500 Quick Disk made from tapes: {title}',
         files=[('s', 3, f'qd:{M15}/{fa}')], late=[] if fb == '-' else [('s', 3, f'qd:{M15}/{fb}', 35)], reset=True,
         steps=[('wait', 4), ('type', 'Q'), ('wait', 40), ('type', key), ('wait', 30), ('shot', 'a'), ('type', key), ('wait', 20),
                ('shot', 'b')])
    if n < 5:                         # the same tapes mounted as the Quick Disk directly (the core shows them as that disk)
        test(f'N{n + 1:02d}', 'MZ1500', f'MZ-1500 tapes mounted as the Quick Disk: {title}',
             files=[('s', 3, f'{M15}/{fa}')], late=[] if fb == '-' else [('s', 3, f'{M15}/{fb}', 35)], reset=True,
             steps=[('wait', 4), ('type', 'Q'), ('wait', 40), ('type', key), ('wait', 30), ('shot', 'a'), ('type', key),
                    ('wait', 20), ('shot', 'b')])

# MZ-800 tapes whose header carries a loader (exec 1108, in the MZF comment area loaded at 10F0): it relocates
# itself and reads the body with the ROM's tape routine.
for n, f in enumerate(['Jetman-S.mzf', 'Inparadi.mzf', 'Silents2.mzf', 'Boulder.mzf', 'Robo2-De.mzf']):
    test(f'H{n + 1:02d}', 'MZ800', f'MZ-800 tape with a header loader (exec 1108): {f}', files=[('s', 0, f'{GAMES800}/{f}')],
         opts=[FAST_TAPE(6)], reset=True,
         steps=[('wait', 6), ('type', 'C'), ('wait', 5), ('type', 'C'), ('wait', 40), ('shot', 'a'), ('wait', 30), ('shot', 'b')])

# More MZ-1500 tapes (single programs that start from tape).
for n, (title, f) in enumerate([
        ('Diamond Chase', 'Diamond Chase (1984)(Oak Corp)(Mac Tabata)(TMK).mzt'),
        ('Hashire! Skyline', 'Hashire! Skyline (1985)(Compac).mzt'),
        ('HP-Oushou', 'HP-Oushou (1984)(SPS).mzt'),
        ('Ice Block', 'Ice Block (1984)(DB-Soft)(Yuji Yoshida).MZT'),
        ('Jan-kyou', 'Jan-kyou (1984)(Hudson Soft).mzt'),
        ('Nonbarla Panic', 'Nonbarla Panic (1985)(Compac)(Shinsuke Nakamura).mzt'),
        ('Punch Ball Mario Bros.', 'Punch Ball Mario Bros. (1984)(Hudson Soft)(Masaaki Kikuta).mzt'),
        ('Sonic Birds', 'Sonic Birds (1984)(Compac).mzt'),
        ('Yakyu-kyou', 'Yakyu-kyou (1984)(Hudson Soft).mzt'),
        ('Youkai Toubatsu Hidejirou', 'Youkai Toubatsu Hidejirou (1987)(Takeshi Maruyama) Side A.mzt'),
        ('Excite 4nin Mahjong', 'Excite 4nin Mahjong (1984)(Tecno Soft).mzt'),
        ('Dezeni Land', 'Dezeni Land (1984)(Hudson)(Tape 1).mzt')]):
    test(f'C{n + 13:02d}', 'MZ1500', f'MZ-1500 tape: {title}', files=[('s', 0, f'{M15}/{f}')], opts=[FAST_TAPE(6)], reset=True,
         steps=[('wait', 6), ('type', 'C'), ('wait', 5), ('type', 'C'), ('wait', 35), ('shot', 'a'), ('wait', 20), ('shot', 'b')])

# MZ-80B bad dumps: sectors with CRC errors in the EDSK; the IPL should report a loading error, not hang.
# OSD Floppy CRC Errors: DISK37 with Report (the IPL says "Loading error"), DISK38 with the default Ignore (boots).
for n, (d, rep) in enumerate([('DISK37.DSK', 1), ('DISK38.DSK', 0)]):
    test(f'T{n + 27:02d}', 'MZ80B', f'MZ-80B floppy with bad sectors: {d}, CRC errors {"reported" if rep else "ignored"}',
         files=[('s', 1, f'{RB}/{d}')], opts=[(*osd('Floppy CRC Errors=Ignore')[0][:2], rep)], reset=True,
         steps=[('wait', 25), ('shot', 'a'), ('wait', 20), ('shot', 'b'), ('wait', 60), ('shot', 'c')])

# Floppy write: CP/M 4.1 saves a file (SAVE 1 TEST.COM) on a copy of its system disk; DIR shows it, and the image
# fetched back has the directory entry.
test('W03', 'MZ800', 'MZ-800 floppy write: CP/M 4.1 SAVE 1 TEST.COM', files=[('s', 1, f'{DSK}/CPMv41 System.dsk')], reset=True,
     steps=[('wait', 15), ('type', 'SAVE 1 TEST.COM\n'), ('wait', 6), ('type', 'DIR\n'), ('wait', 4), ('shot', 'dir'),
            ('fetch', 0)])

# MZ-2000 tape search: one tape image with MZ-1Z002 BASIC, Piranha-kun and Explorer; LOAD "EXPLORER" in BASIC passes
# over Piranha-kun's record (the deck's APSS seek) and loads Explorer.
test('K09', 'MZ2000', 'MZ-2000 BASIC LOAD "EXPLORER" finds the third program on the tape image (skips Piranha-kun)',
     files=[('s', 0, 'gen:mz2000_search')], opts=[FAST_TAPE(6)], reset=True,
     steps=[('wait', 25), ('shot', 'basic'), ('type', 'LOAD "EXPLORER"\n'), ('wait', 40), ('shot', 'loaded')])

# OSD Tape Image Start: Direct: the tape image's first program goes into RAM and starts (no L, no tape wait);
# the second is then on the tape for LOAD.
test('L13', 'MZ700', 'Tape Image Start Direct: BASIC 1Z-013B starts by itself, LOAD gets the next program, LIST',
     files=[('s', 0, 'gen:td_basic')], opts=[FAST_TAPE(5)] + osd('Tape Image Start=Direct'), reset=True,
     steps=[('wait', 8), ('shot', 'basic'), ('type', 'LOAD\n'), ('wait', 12), ('type', 'LIST\n'), ('wait', 4), ('shot', 'list')])

PACK800 = os.path.join(ROOT, 'out/SharpMZ-tester-pack-20261004/games/SharpMZ/MZ-800')
for n, game in (('L14', 'Exolon'), ('L15', 'Knight Lore')):     # a loading screen, then the game it loads from tape
    test(n, 'MZ800', f'Tape Image Start Direct: {game} (screen loader starts, loads the game from the tape)',
         files=[('s', 0, f'{PACK800}/{game}.mzt')], opts=[FAST_TAPE(6)] + osd('Tape Image Start=Direct'), reset=True,
         steps=[('wait', 6), ('shot', 'loader'), ('wait', 30), ('shot', 'game')])

# MZ-80B/2000 Boot Reset on (EeDee): a disk mounted while the IPL waits, then a reset, boots it; a second reset goes
# back to the IPL and boots it again. Boot Reset used to hold the IPL ROM at 0000, so the IPL restarted for ever.
RESET_KEYS = '29+56+100'
test('F03', 'MZ80B', 'MZ-80B Boot Reset: disk mounted at the IPL, reset boots CP/M 2.2; reset again boots it again',
     files=[], late=[('s', 1, f'{SW}/idealine/mz-80b/rb_DSK/DSK/DISK01.DSK', 8)], opts=osd('MZ-80B/2000 Boot Reset=On'),
     steps=[('wait', 12), ('keys', RESET_KEYS), ('wait', 15), ('shot', 'cpm'), ('keys', RESET_KEYS), ('wait', 15), ('shot', 'again')])
test('F04', 'MZ2000', 'MZ-2000 Boot Reset: TF-DOS disk mounted at the IPL, reset boots it',
     files=[], late=[('s', 1, f'{SW}/fukui-mz2000/brave.d88', 8)], opts=osd('MZ-80B/2000 Boot Reset=On'),
     steps=[('wait', 12), ('keys', RESET_KEYS), ('wait', 20), ('shot', 'boot')])

# OSD Tape Messages: the overlay names the record the tape image is at (TAPE 1/2 S-BASIC on mounting, TAPE 2/2 R.P.S.
# once BASIC is in and the tape has stopped).
test('L16', 'MZ700', 'Tape Messages overlay: after L loads BASIC, TAPE 2/2 R.P.S. at the bottom for 3 s',
     files=[('s', 0, 'gen:td_basic')], opts=[FAST_TAPE(6)] + osd('Tape Messages=On'), reset=True,
     steps=[('type', 'L\n')] + [s for k in range(24) for s in (('wait', 0.3), ('shot', f'{k:02d}'))])

# MZ-80A floppy: the interface ROM (F000, banks 1Ah-1Bh) boots SA-6510 Disk BASIC: F at the monitor, Return for drive 1.
test('F02', 'MZ80A', 'MZ-80A floppy: F, Return boots SA-6510 Disk BASIC from drive A',
     files=[('s', 1, f'{SW}/idealine/mz-80a/SA-6510bootdisk/SA-6510.DSK')], reset=True,
     steps=[('wait', 4), ('type', 'F\n'), ('wait', 2), ('type', '\n'), ('wait', 12), ('shot', 'basic')])

# OSD Keyboard Layout: PC. Every punctuation key, typed as on a US PC keyboard, shows its own character
# (characters the model doesn't have type nothing; tools/keymap_measure.py --verify checks the same in the sim).
PCTEXT = '!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~'
test('K11', 'MZ80A', 'PC keyboard layout on the MZ-80A: every punctuation key at the monitor',
     opts=[PC_KEYS], steps=[('wait', 4), ('pctype', 'A' + PCTEXT + 'B'), ('wait', 2), ('shot', 'pc')])
test('K12', 'MZ700', 'PC keyboard layout on the MZ-700: every punctuation key at the monitor',
     opts=[PC_KEYS], steps=[('wait', 4), ('pctype', 'A' + PCTEXT + 'B'), ('wait', 2), ('shot', 'pc')])
test('K13', 'MZ80K', 'PC keyboard layout on the MZ-80K: every punctuation key at the monitor',
     opts=[PC_KEYS], steps=[('wait', 4), ('pctype', 'A' + PCTEXT + 'B'), ('wait', 2), ('shot', 'pc')])
test('K14', 'MZ1200', 'MZ-1200 keys (it had the MZ-80A keymap on the MZ-80K monitor): letters, digits, punctuation',
     opts=[PC_KEYS], steps=[('wait', 4), ('pctype', 'ABC123' + PCTEXT), ('wait', 2), ('shot', 'pc')])

# MZ-800 joystick through a virtual Xbox 360 pad (tools/mister_keys.py joy): right + B held (MiSTer's SNES layout: the core's first button is the east button, Xbox B; Xbox A gives fire 2, D7), tests/mz800/joytest.mzf
# reads F0/F1 with the 8255 strobes and prints them; the sim (joy_mz800, --joy0 17) gives E7 FF E7 FF.
test('J01', 'MZ800', 'MZ-800 joystick: right + fire 1 held on a virtual pad, joytest prints E7 FF E7 FF',
     files=[('s', 0, f'{TESTS}/joytest.mzf')], opts=[FAST_TAPE(4)], reset=True,
     steps=[('joy', 'right b'), ('wait', 6), ('type', 'C'), ('wait', 20), ('shot', 'joy'), ('joy', '')])

# 1.44 MB disk as CP/M 4.1's drive C: (OSD Floppy > Drive B Unit: 3rd = unit 2), a blank CP/M (E5) image in drive B:
# DIR C:, SAVE a file there, DIR C: again; the image is fetched back.
test('F01', 'MZ800', 'MZ-800 CP/M 4.1: 1.44 MB disk as drive C: (Drive B unit 2): DIR, SAVE, DIR',
     files=[('s', 1, f'{DSK}/CPMv41 System.dsk'), ('s', 2, 'gen:blank144')], opts=osd('Drive B Unit=1'), reset=True,
     steps=[('wait', 15), ('type', 'DIR C:\n'), ('wait', 6), ('shot', 'dir_empty'), ('type', 'SAVE 1 C:TEST.COM\n'),
            ('wait', 6), ('type', 'DIR C:\n'), ('wait', 6), ('shot', 'dir_saved'), ('fetch', 1)])

# MZ-800 border (OSD Display > MZ-800 Border): Cybernoid and CP/M 4.1 with the border shown.
test('T29', 'MZ800', 'MZ-800 border on: Cybernoid', files=[('s', 0, f'{GAMES800}/Cyberno.mzf')], opts=[FAST_TAPE(6)] + osd('MZ-800 Border=On'),
     reset=True, steps=[('wait', 6), ('type', 'C'), ('wait', 5), ('type', 'C'), ('wait', 45), ('shot', 'a')])
test('T31', 'MZ800', 'MZ-800 border on: a program sets the border to light red (OUT (CF) with B = 06)',
     files=[('s', 0, f'{TESTS}/border.mzf')], opts=[FAST_TAPE(6)] + osd('MZ-800 Border=On'), reset=True,
     steps=[('wait', 6), ('type', 'C'), ('wait', 5), ('type', 'C'), ('wait', 15), ('shot', 'a')])
test('T30', 'MZ800', 'MZ-800 border on: CP/M 4.1', files=[('s', 1, f'{DSK}/CPMv41 System.dsk')], opts=osd('MZ-800 Border=On'), reset=True,
     steps=[('wait', 15), ('shot', 'boot')])

# More MZ-2000 tapes (software/mz2200): the IPL loads them from the tape image (fast tape 32x).
for n, f in enumerate(['Explorer (1989)(Micom Basic)(Taka Yamashita) [CT].mzt', 'Flicky Mz-2200_Loader.mzt',
                       'Itasandrias (1983)(Hudson Soft)(Fumihiko Itagaki) [CT].mzt',
                       'Piranha-Kun no Isshukan (1983)(Enix)(Atsushi Shirai) [CT].mzt',
                       'Project A (1984)(Pony Canyon)(Tatsuji Otsuka) [CT].mzt', 'Puckn Boy.mzt',
                       'Super Doors (1983)(Hudson Soft)(TNT) [CT].mzt']):
    test(f'K{n + 1:02d}', 'MZ2000', f'MZ-2000 tape: {f}', files=[('s', 0, f'{SW}/mz2200/{f}')], opts=[FAST_TAPE(6)], reset=True,
         steps=[('wait', 45), ('shot', 'a'), ('wait', 45), ('shot', 'b'), ('wait', 120), ('shot', 'c')])

test('K08', 'MZ80B', 'MZ-80B tape: Puckn Boy (stays at "IPL is loading" on the MZ-2000)', files=[('s', 0, f'{SW}/mz2200/Puckn Boy.mzt')],
     opts=[FAST_TAPE(5)], reset=True, steps=[('wait', 45), ('shot', 'a'), ('type', ' '), ('wait', 5), ('type', 'S'), ('wait', 10),
                                             ('shot', 'b')])

# Load Direct: Start Program (default): the core boots, restores 10F0-11FF and jumps to exec (rtl/direct_start.sv).
YB = os.path.join(SW, 'Year-Based Collection of Games for the Sharp MZ-80K Line of Home Computers v1.0')
def yb(year, machine, name):
    return f'{YB}/{year}/{machine}/{name}'
for name, model, desc, src, wait in [
        ('L01', 'MZ800', 'Load Direct starts Jumpin\' Jack (exec 1150, inside the MZF header)', yb(1988, 'MZ-800', "Jumpin' Jack v01 (1988)(Wermouska Software).mzf"), 12),
        ('L02', 'MZ800', 'Load Direct starts The Way of the Exploding Fist (loads and runs at 10F0)', yb(1987, 'MZ-800', 'Way of the Exploding Fist, The (1987)(Michal Kreidl Software).mzf'), 12),
        ('L03', 'MZ800', "Load Direct starts Solomon's Key (exec 1108)", yb(1989, 'MZ-800', "Solomon's Key (1989)(DS Software).mzf"), 12),
        ('L04', 'MZ800', 'Abu Simbel Profanation: title text whole, no stripes (16-colour colour search)', yb(1985, 'MZ-800', 'Abu Simbel Profanation (1985)(Dinamic Software).mzf'), 12),
        ('L05', 'MZ800', 'Planetoids v3.1: instructions screen (palette reset)', yb('19xx', 'MZ-800', 'Planetoids v3.1 (19xx)(Sharp Club Brno).mzf'), 12),
        ('L06', 'MZ800', 'Antiriad (Eng): credits or the noise band? (mz800emu reaches the credits only through a bug)', yb(1986, 'MZ-800', 'Sacred Armour of Antiriad, The (Eng)(1986)(Proton Software).mzf'), 20),
        ('L07', 'MZ700', 'Load Direct on the MZ-700: Base Zero', yb(1983, 'MZ-700', 'Base Zero (1983).mzf'), 12),
        ('L08', 'MZ80K', 'Load Direct on the MZ-80K: Galactic Attack', yb(1980, 'MZ-80K', 'Galactic Attack (1980)(Cromwell Computing).mzf'), 8),
        ('L09', 'MZ80A', 'Load Direct on the MZ-80A: Super Fire', yb(1980, 'MZ-80A', 'Super Fire (1980).mzf'), 8)]:
    test(name, model, desc, files=[('f', 2, src)], steps=[('wait', wait), ('shot', 'run')])

# MZ-700 video (tester report 2026-10-13, G/F/E): Load Direct, then the picture.
test('X01', 'MZ700', 'MZ-700: Metro-Cross title in place (the MZ-80A E200 scroll no longer acts on the MZ-700)',
     files=[('f', 2, yb(1989, 'MZ-700', 'Metro-Cross (1989)(Namco).mzt'))], steps=[('wait', 14), ('shot', 'title')])
test('X02', 'MZ700', 'MZ-700 PCG-700: line 2 shows the programmed EF (set 1), A, the box (set 2); the cursor is the EF',
     files=[('f', 2, os.path.join(ROOT, 'verilator/tests/mz700/pcg700.mzf'))], steps=[('wait', 5), ('shot', 'pcg')])
test('X03', 'MZ700', 'MZ-700 Region Japan: Donkey Gorilla title in katakana',
     files=[('f', 2, yb('19xx', 'MZ-700', 'Donkey Gorilla (19xx)(Tecno Soft).mzt'))], opts=osd('Region=Japan'),
     steps=[('wait', 20), ('shot', 'title')])
test('X04', 'MZ700', 'MZ-700 Region Japan: Tiny Xevious in play (the panel on the right)',
     files=[('f', 2, yb('19xx', 'MZ-700', 'Tiny Xevious (19xx)(Namco).mzt'))], opts=osd('Region=Japan'),
     steps=[('wait', 12), ('type', ' '), ('wait', 8), ('shot', 'play')])
# Puckn Boy after MZ-1Z002 BASIC from one tape image (the CMT used to keep sending BASIC's backup copy).
test('L10', 'MZ2000', 'MZ-2000: MZ-1Z002 BASIC from the IPL, then MON, L: Puckn Boy loads and starts',
     files=[('s', 0, os.path.join(ROOT, 'verilator/out/pb2/t.mzt'))], opts=[FAST_TAPE(5)], reset=True,
     steps=[('wait', 30), ('shot', 'basic'), ('type', 'MON\n'), ('wait', 3), ('type', 'L\n'), ('wait', 3), ('type', '\n'),
            ('wait', 40), ('shot', 'pucknboy')])
# Dezeni Land (MZ-1500): C at the IPL menu, Tape 1 loads, N + Return at the Quick Disk question, title screen.
test('L11', 'MZ1500', 'MZ-1500: Dezeni Land Tape 1 from a tape image (C), N at the QD question, title',
     files=[('s', 0, f'{SW}/mz1500/Dezeni Land (1984)(Hudson)(Tape 1).mzt')], opts=[FAST_TAPE(5)], reset=True,
     steps=[('wait', 12), ('shot', 'menu'), ('type', 'C'), ('wait', 60), ('shot', 'qd'), ('type', 'N\n'), ('wait', 8), ('shot', 'title')])
# Tape Image order (first to last, as the old core's tape queue): BASIC 1Z-013B is record 1 (L in the monitor), a
# BASIC program record 2 (LOAD in BASIC), LIST shows it.
test('L12', 'MZ700', 'MZ-700 Tape Image order: L loads BASIC 1Z-013B (record 1), LOAD the BASIC program (record 2)',
     files=[('s', 0, 'gen:basic_mzt')], opts=[FAST_TAPE(5)], reset=True,
     steps=[('wait', 4), ('type', 'L\n'), ('wait', 30), ('shot', 'basic'), ('type', 'LOAD\n'), ('wait', 15),
            ('type', 'LIST\n'), ('wait', 3), ('shot', 'list')])

# Printer: the core's UART pins are the MiSTer's /dev/ttyS1, so what the machine prints is captured there (9600 8N1,
# no daemon needed) and compared with the simulation's bytes (verilator/tests/expected/prn_*.txt).
PRN = os.path.join(ROOT, 'verilator/tests/printer')
test('P01', 'MZ700', 'Printer (UART): prntest prints two lines; the bytes on /dev/ttyS1 match the sim (prn_mz700)',
     files=[('f', 2, f'{PRN}/prntest.mzf')], opts=osd('Printer=1'),
     steps=[('capture', 'start'), ('wait', 10), ('capture', 'prn_mz700'), ('shot', 'done')])
test('P02', 'MZ700', 'Printer Charset ASCII: Sharp lowercase and bare CRs arrive as ASCII with CR LF (prn_ascii_mz700)',
     files=[('f', 2, f'{PRN}/prnsharp.mzf')], opts=osd('Printer=1, Printer Charset=ASCII'),
     steps=[('capture', 'start'), ('wait', 10), ('capture', 'prn_ascii_mz700'), ('shot', 'done')])

test('P03', 'MZ700', 'MZ-700 BASIC: LIST/P, then PRINT/P "HELLO" (the sim seemed to drop the PRINT/P)',
     files=[('f', 2, yb('BASIC', 'MZ-700', 'BASIC 1Z-013B.mzf'))], opts=osd('Printer=1'),
     steps=[('capture', 'start'), ('wait', 6), ('type', '10 REM TEST\n'), ('wait', 1), ('type', 'LIST/P\n'), ('wait', 4),
            ('type', 'PRINT/P "HELLO"\n'), ('wait', 4), ('shot', 'screen'), ('capture', 'show')])

# MZ-1500 tester reports. Zulpoko Daisakusen is a BASIC program, not a standalone game: its header says type 02, which
# MZ-5Z001 (either copy, software/mz1500 or the collection's BASIC/MZ-1500) rejects as an illegal filemode, probably a Quick
# Disk file type kept in a tape conversion. As type 05 it loads, and stops at "Illegal data error in 150", the same in
# mz1500emu, so the file needs another BASIC or is damaged; the core matches the emulator. Maze Land (Enix) loads three ways.
test('Z01', 'MZ1500', 'MZ-1500: MZ-5Z001 then Zulpoko as type 05 AUTO RUN: "Illegal data error in 150", as mz1500emu',
     files=[('s', 0, 'gen:zulpoko')], opts=[FAST_TAPE(6)], reset=True,
     steps=[('wait', 6), ('type', 'C'), ('wait', 60), ('shot', 'run')])
test('A01', 'MZ1500', 'MZ-1500 PSG stereo: left PSG 440 Hz, right PSG 880 Hz (HDMI audio from the capture card)',
     files=[('f', 2, os.path.join(ROOT, 'verilator/tests/mz1500/psgstereo.mzf'))], steps=[('wait', 6), ('audio', 'psg')])
TESTERS = f'{SW}/testers-2026-10-14'
test('H06', 'MZ800', 'MZ-800 Cybernoid (Profi), four files on one tape: loading screen, then the menu (mz800emu: menu by ~400 s at real speed)',
     files=[('s', 0, f'{TESTERS}/Cybernoid (Profi) 4 parts.mzt')], reset=True,
     steps=[('wait', 6), ('type', 'C'), ('wait', 60), ('shot', 'a'), ('wait', 60), ('shot', 'b'), ('wait', 120), ('shot', 'c'),
            ('wait', 200), ('shot', 'd')])
test('H08', 'MZ800', 'MZ-800 Cybernoid (Profi), four files, real speed, VRAM Wait On',
     files=[('s', 0, f'{TESTERS}/Cybernoid (Profi) 4 parts.mzt')], opts=osd('VRAM Wait=On'), reset=True,
     steps=[('wait', 6), ('type', 'C'), ('wait', 120), ('shot', 'b'), ('wait', 120), ('shot', 'c')])
test('H07', 'MZ800', 'MZ-800 Cybernoid (Profi), four files, Fast Tape Fastest',
     files=[('s', 0, f'{TESTERS}/Cybernoid (Profi) 4 parts.mzt')], opts=[FAST_TAPE(0)], reset=True,
     steps=[('wait', 6), ('type', 'C'), ('wait', 30), ('shot', 'a'), ('wait', 60), ('shot', 'b'), ('wait', 60), ('shot', 'c')])
# MZ-1500 programs that scan the keyboard (and more) from Z80 PIO interrupts on PA4 = the 8253's OUT0 (2026-10-14).
test('Q06', 'MZ1500', 'MZ-1500 Batten Tanuki: side B, Return, then F1 at "F1 -- START" starts the game (was ignored)',
     files=[('s', 3, f'{TESTERS}/Batten Tanuki no Daibouken (Side A)(1986)(Tecno Soft).qdf')],
     late=[('s', 3, f'{TESTERS}/Batten Tanuki no Daibouken (Side B)(1986)(Tecno Soft).qdf', 14)], reset=True,
     steps=[('wait', 4), ('type', 'Q'), ('wait', 14), ('type', '\n'), ('wait', 10), ('shot', 'prompt'), ('keys', '59'),
            ('wait', 8), ('shot', 'f1')])
test('Q07', 'MZ1500', 'MZ-1500 Nobunaga no Yabou: F1 loads TITLE, which wants side B (KOEI ...): side B mounted, the game',
     files=[('s', 3, f'{TESTERS}/Nobunaga no Yabou (Side A)(1984)(Koei).qdf')],
     late=[('s', 3, f'{TESTERS}/Nobunaga no Yabou (Side B)(1984)(Koei).qdf', 75)], reset=True,
     steps=[('wait', 4), ('type', 'Q'), ('wait', 40), ('shot', 'prompt'), ('keys', '59'), ('wait', 25), ('shot', 'f1'),
            ('wait', 45), ('shot', 'sideb')])
test('Q08', 'MZ1500', 'MZ-1500 Earthbound: title (PCG), then side B and SPACE: part 1 (EmuZ-1500 the same)',
     files=[('s', 3, f'{TESTERS}/Earthbound (Side A)(1984)(Xtalsoft).qdf')],
     late=[('s', 3, f'{TESTERS}/Earthbound (Side B)(1984)(Xtalsoft).qdf', 120)], reset=True,
     steps=[('wait', 4), ('type', 'Q'), ('wait', 50), ('shot', 'title'), ('wait', 70), ('shot', 'sideb'), ('type', ' '),
            ('wait', 40), ('shot', 'part1')])
test('Q09', 'MZ1500', 'MZ-1500 3-D Golf: title, "turn the QD to side B and press F1": side B, F1, the game',
     files=[('s', 3, f'{TESTERS}/3-D Golf Simulation (Side A)(1984)(T&E Soft).qdf')],
     late=[('s', 3, f'{TESTERS}/3-D Golf Simulation (Side B)(1984)(T&E Soft).qdf', 60)], reset=True,
     steps=[('wait', 4), ('type', 'Q'), ('wait', 45), ('shot', 'a'), ('wait', 20), ('keys', '59'), ('wait', 40), ('shot', 'b')])
test('Z04', 'MZ1500', 'MZ-1500: MZ-5Z001 and Zulpoko as one tape in the Quick Disk slot: Q, LOAD "ZULPOKO", RUN: its title',
     files=[('s', 3, 'gen:qdtape_zulpoko')], reset=True,
     steps=[('wait', 4), ('type', 'Q'), ('wait', 30), ('shot', 'basic'), ('type', 'LOAD "ZULPOKO"\n'), ('wait', 15),
            ('type', 'RUN\n'), ('wait', 30), ('shot', 'run')])
test('Z02', 'MZ1500', 'MZ-1500: Maze Land from the tape image, C at the IPL',
     files=[('s', 0, yb(1983, 'MZ-1500', 'Maze Land (1983)(Enix).mzf'))], opts=[FAST_TAPE(6)],
     steps=[('wait', 12), ('shot', 'menu'), ('type', 'C'), ('wait', 5), ('shot', 'loading'), ('wait', 30), ('shot', 'run')])
test('Z03', 'MZ1500', 'MZ-1500: Maze Land by Load Direct to RAM (starts by itself)',
     files=[('f', 2, yb(1983, 'MZ-1500', 'Maze Land (1983)(Enix).mzf'))],
     steps=[('wait', 12), ('shot', 'run')])

# 3-D Maze: two different programs. The MZ-80K one (Knights TV) runs under SP-5025; mz-archive's Tests/3-D MAZE.MZF is
# the MZ-80A one (SA-5510), which looked garbled when run on the MZ-80K.
for name, model, interp, prog in [
        ('M01', 'MZ80K', yb('BASIC', 'MZ-80K', 'BASIC SP-5025ext.mzf'), yb('19xx', 'MZ-80K', '3D-Maze (19xx)(Knights TV & Computers).mzf')),
        ('M02', 'MZ80A', yb('BASIC', 'MZ-80A', 'BASIC SA-5510.mzf'), yb('19xx', 'MZ-80A', '3-D Maze (19xx).mzf'))]:
    test(name, model, f'{model} 3-D Maze under its own BASIC (Load Direct BASIC, tape image program, LOAD, RUN)',
         files=[('f', 2, interp), ('s', 0, prog)], opts=[FAST_TAPE(6)],
         steps=[('wait', 6), ('type', 'LOAD\n'), ('wait', 25), ('shot', 'load'), ('type', 'RUN\n'), ('wait', 15), ('shot', 'run'),
                ('wait', 15), ('shot', 'later')])

# Scandoubler (OSD Display > Scandoubler Fx; also MiSTer.ini forced_scandoubler): the doubled 31 kHz picture.
SDFX = lambda v: (44, 3, v)                # 0 None, 1 HQ2x, 2-4 CRT 25/50/75%
test('V01', 'MZ700', 'Scandoubler CRT 50%: MZ-700 monitor', opts=[SDFX(3)], steps=[('wait', 6), ('shot', 'boot')])
test('V02', 'MZ80A', 'Scandoubler HQ2x: MZ-80A monitor (60 Hz, 8 MHz pixels)', opts=[SDFX(1)], steps=[('wait', 6), ('shot', 'boot')])
test('V03', 'MZ800', 'Scandoubler CRT 25%: MZ-800 CP/M 4.1 (640 mode)', files=[('s', 1, f'{DSK}/CPMv41 System.dsk')], opts=[SDFX(2)],
     reset=True, steps=[('wait', 15), ('shot', 'boot')])
test('V04', 'MZ800', 'Scandoubler CRT 50% with the MZ-800 border', files=[('s', 0, f'{TESTS}/border.mzf')],
     opts=[FAST_TAPE(6), SDFX(3)] + osd('MZ-800 Border=On'), reset=True,
     steps=[('wait', 6), ('type', 'C'), ('wait', 5), ('type', 'C'), ('wait', 15), ('shot', 'a')])
test('V05', 'MZ80B', 'Scandoubler CRT 50%: MZ-80B (80 columns, 16 MHz pixels)', files=[('s', 1, f'{RB}/DISK23.DSK')], opts=[SDFX(3)],
     reset=True, steps=[('wait', 20), ('shot', 'boot')])

# Linux input key codes (uinput); a leading '-' holds shift (mrext keyboard-raw).
KEYS = {'\n': 28, ' ': 57, '-': 12, '=': 13, ';': 39, ',': 51, '.': 52, '/': 53, ':': 40, '*': -40, '"': -3}   # Sharp layout by position: PC ' is the : key (shift *), shift+2 is "
KEYS.update({c: k for c, k in zip('1234567890', range(2, 12))})
KEYS.update({c: k for c, k in zip('QWERTYUIOP', range(16, 26))})
KEYS.update({c: k for c, k in zip('ASDFGHJKL', range(30, 39))})
KEYS.update({c: k for c, k in zip('ZXCVBNM', range(44, 51))})
# ('pctype', text): a US PC keyboard (OSD Keyboard Layout: PC); letters unshifted, shifted symbols as SHIFT chords.
PCKEYS = {c: str(k) for c, k in KEYS.items() if c.isalnum() or c in '\n -=;,./'}
PCKEYS.update({'[': '26', ']': '27', "'": '40', '`': '41', '\\': '43'})
PCKEYS.update({c: f'42+{k}' for c, k in zip('!@#$%^&*()', range(2, 12))})
PCKEYS.update({c: f'42+{k}' for c, k in zip('_+{}:"~|<>?', (12, 13, 26, 27, 39, 40, 41, 43, 51, 52, 53))})


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, check=True, **kw)


# HDMI capture card for audio steps (it shows mister126's output; tools on misterubuntu).
CAPTURE_HOST = os.environ.get('CAPTURE_HOST', 'misterubuntu')
CAPTURE_PCM = os.environ.get('CAPTURE_PCM', 'plughw:CARD=U25773,DEV=0')
REFS = os.path.join(ROOT, 'tools/mister_refs.json')   # md5 of each screenshot from a good run (--update-refs)
# One ssh connection for the whole run (each step was a new connection, about half a second).
SSH_OPTS = ['-o', 'ControlMaster=auto', '-o', 'ControlPath=/tmp/mister_test_%r@%h:%p', '-o', 'ControlPersist=120']


def md5(path):
    return hashlib.md5(open(path, 'rb').read()).hexdigest()


class Mister:
    def __init__(self, host):
        self.host = host
        self.target = host if '@' in host or host == 'mister' else f'root@{host}'
        self.remote_md5 = {}

    def ssh(self, cmd, capture=False):
        r = subprocess.run(['ssh'] + SSH_OPTS + [self.target, cmd], check=True, capture_output=capture, text=True)
        return r.stdout if capture else None

    def put(self, local, remote):
        """Copy a file, unless the MiSTer already has it (md5 from scan())."""
        if self.remote_md5.get(remote) == md5(local):
            return
        subprocess.run(['scp', '-q'] + SSH_OPTS + [local, f'{self.target}:{remote}'], check=True)
        self.remote_md5[remote] = md5(local)

    def scan(self, *dirs):
        """md5 of the files already in these directories on the MiSTer, so put() can skip unchanged ones."""
        out = self.ssh('md5sum ' + ' '.join(f'"{d}"/* "{d}"/*/* 2>/dev/null' for d in dirs) + ' || true', True)
        for line in out.splitlines():
            h, _, path = line.partition('  ')
            if path:
                self.remote_md5[path] = h

    def screen_md5(self, name='_poll.png'):
        """Take a screenshot and return its md5 (the PNG is the same for the same picture)."""
        self.cmd(f'screenshot {name}')
        time.sleep(0.8)
        out = self.ssh(f'md5sum {FAT}/screenshots/{name} 2>/dev/null; rm -f {FAT}/screenshots/{name}', True)
        return out.split()[0] if out else ''

    def wait_for(self, seconds, ref):
        """Wait up to SECONDS; with reference md5s (a blinking cursor gives two), return when the screen matches one."""
        end = time.time() + seconds
        if not ref:
            time.sleep(seconds)
            return
        time.sleep(min(2, seconds))
        while time.time() < end:
            if self.screen_md5() in ref:
                return
            time.sleep(min(2, max(0, end - time.time())))

    def cmd(self, c):
        self.ssh(f'echo "{c}" > /dev/MiSTer_cmd')

    KEYS_TOOL = f'{FAT}/tools/mister_keys.py'

    def start_keys(self):
        """Copy tools/mister_keys.py to the SD card (/media/fat/tools) and start its uinput keyboard daemon."""
        self.ssh(f'mkdir -p {FAT}/tools')
        self.put(os.path.join(ROOT, 'tools/mister_keys.py'), self.KEYS_TOOL)
        self.ssh(f'python3 {self.KEYS_TOOL} start')

    def key(self, code):
        self.ssh(f'python3 {self.KEYS_TOOL} key {code}')

    def type(self, text):
        codes = ' '.join(str(KEYS[c]) for c in text.upper())
        self.ssh(f'python3 {self.KEYS_TOOL} key {codes}')
        time.sleep(0.2 * len(text))


# --basic N: BASIC program triage. The interpreter is loaded with Load Direct (it starts at once), the program is
# the tape image; LOAD, RUN, screenshots. A seeded random sample of N programs per model (type 05 for the MZ-700,
# type 02 in the MZ-80K and MZ-80A folders) from the year-based collection.
BASIC_FOR = {'MZ700': ('X7', 'MZ-700', 0x05, yb('BASIC', 'MZ-700', 'BASIC 1Z-013B.mzf')),
             'MZ80K': ('XK', 'MZ-80K', 0x02, yb('BASIC', 'MZ-80K', 'BASIC SP-5025ext.mzf')),
             'MZ80A': ('XA', 'MZ-80A', 0x02, yb('BASIC', 'MZ-80A', 'BASIC SA-5510.mzf'))}


def basic_tests(n, seed=1):
    import random
    rng = random.Random(seed)
    out = []
    for model, (prefix, folder, typ, interp) in BASIC_FOR.items():
        progs = []
        for root, _, fs in os.walk(YB):
            if os.path.basename(root) != folder or '/BASIC/' in root + '/':
                continue
            for f in fs:
                p = os.path.join(root, f)
                if f.lower().endswith('.mzf') and open(p, 'rb').read(1) == bytes([typ]):
                    progs.append(p)
        progs.sort()
        for i, p in enumerate(rng.sample(progs, min(n, len(progs)))):
            out.append(dict(name=f'{prefix}{i + 1:02d}', model=model, desc=f'{folder} BASIC: {os.path.basename(p)[:-4]}',
                            files=[('f', 2, interp), ('s', 0, p)], opts=[FAST_TAPE(6)], reset=False, late=[],
                            steps=[('wait', 6), ('type', 'LOAD\n'), ('wait', 25), ('shot', 'load'), ('type', 'RUN\n'),
                                   ('wait', 10), ('shot', 'run'), ('wait', 20), ('shot', 'later')]))
    return out


# --quick: one or two tests per model and feature (about 15 minutes).
QUICK = {'T01', 'T02', 'T03', 'T04', 'T05', 'T06', 'T07', 'T08', 'T09', 'T13', 'T21', 'T22', 'T25', 'T26',
         'W01', 'L01', 'L04', 'L05', 'L07', 'L08', 'L09', 'L10', 'L12', 'V01', 'X01', 'X02', 'X03', 'X04'}

MENU = f'{FAT}/_SharpMZ Tests'      # a folder starting with _ shows in the MiSTer main menu


AUTOTYPE = f'{FAT}/tools/autotype'


def steps_file(t):
    """The test's steps for mister_keys.py watch: waits, keys (Sharp layout codes from KEYS) and screenshots."""
    out = [f'wait {4 + 2 * len(t["files"]) + (2 if t["reset"] else 0)}']
    for op, arg in t['steps']:
        if op == 'wait':
            out.append(f'wait {arg}')
        elif op == 'type':
            out.append('key ' + ' '.join(str(KEYS[c]) for c in arg.upper()))
        elif op == 'pctype':
            out.append('key ' + ' '.join(PCKEYS[c] for c in arg.upper()))
        elif op == 'keys':
            out.append('key ' + arg)
        elif op == 'shot':
            out.append(f'shot {arg}')
    return '\n'.join(out) + '\n'


def menu_name(t):
    """File name for the menu: test number, description, then the keys to type (an MGL can't type)."""
    keys = [arg.replace('\n', ' Ret') for op, arg in t['steps'] if op in ('type', 'pctype')]
    name = f'{t["name"]} {t["desc"]}'
    name = ''.join(c if c.isalnum() or c in " -+.,'()&" else ' ' for c in name)
    name = ' '.join(name.split())[:70].rstrip(' ,.-')
    if keys:
        hint = ', then '.join(k.strip() for k in keys)[:40]
        name += ' (type ' + ' '.join(''.join(c if c.isalnum() or c in " -+.,()&" else ' ' for c in hint).split()) + ')'
    return name + '.mgl'


def mgl(rbf, t, remote_files):
    x = ['<mistergamedescription>', f'  <rbf>{rbf}</rbf>', f'  <setname same_dir="1">{t["name"]}</setname>']
    for (kind, index, _), path in zip(t['files'], remote_files):
        x.append(f'  <file delay="2" type="{kind}" index="{index}" path="{path}"/>')
    if t['reset']:
        x.append('  <reset delay="1"/>')
    for (kind, index, _, delay), path in zip(t['late'], remote_files[len(t['files']):]):
        x.append(f'  <file delay="{delay}" type="{kind}" index="{index}" path="{path}"/>')
    x.append('</mistergamedescription>')
    return '\n'.join(x) + '\n'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', default='mister', help='ssh host (an ~/.ssh/config alias works)')
    ap.add_argument('--rbf', default=os.path.join(ROOT, 'output_files/SharpMZ.rbf'))
    ap.add_argument('--only')
    ap.add_argument('--quick', action='store_true', help='a short set: one or two tests per model and feature')
    ap.add_argument('--basic', type=int, metavar='N', help='BASIC triage instead: N random BASIC programs per model')
    ap.add_argument('--sweep', nargs=4, metavar=('MODEL', 'SLOT', 'WAIT', 'GLOB'),
                    help='one test per file matching GLOB: mount it in image slot SLOT (0 tape, 1/2 floppy, 3 QD), reset, '
                         'wait WAIT seconds, screenshot (e.g. --sweep MZ80B 1 15 "software/idealine/mz-80b/rb_DSK/DSK/*.DSK")')
    ap.add_argument('--update-refs', action='store_true',
                    help='after the run, keep each screenshot\'s md5 in tools/mister_refs.json (only from a good run)')
    ap.add_argument('--no-refs', action='store_true', help='fixed waits, ignoring tools/mister_refs.json')
    ap.add_argument('--out', default=os.path.join(ROOT, 'out/mister'))
    ap.add_argument('--no-deploy', action='store_true', help='use the RBF already on the MiSTer')
    ap.add_argument('--menu', action='store_true',
                    help=f'only deploy: put each test as an MGL in "{MENU}" (MiSTer main menu) to run by hand')
    a = ap.parse_args()
    pool = basic_tests(a.basic) if a.basic else T
    if a.sweep:
        import glob as _glob
        model, slot, wait, pattern = a.sweep
        steps = [('wait', float(wait)), ('shot', 'boot')]
        if model == 'MZ1500' and slot == '3':     # Quick Disk: Q at the IPL, as the Q tests, then two pictures
            steps = [('wait', 4), ('type', 'Q'), ('wait', float(wait)), ('shot', 'a'), ('wait', 20), ('shot', 'b')]
        pool = [dict(name=f'S{i:02d}', model=model, desc=os.path.basename(f), files=[('s', int(slot), os.path.abspath(f))],
                     opts=[], reset=True, steps=steps, late=[])
                for i, f in enumerate(sorted(_glob.glob(pattern)))]
    tests = [t for t in pool if not a.only or t['name'] in a.only.split(',')]
    if a.quick:
        tests = [t for t in tests if t['name'] in QUICK]
    m = Mister(a.host)
    m.start_keys()
    if not a.menu:                # this script types the keys itself: the menu autotype watcher would type them too
        m.ssh(f'python3 {Mister.KEYS_TOOL} watch-stop')
    stage = os.path.join(a.out, 'stage')
    os.makedirs(stage, exist_ok=True)

    rbf_name = 'SharpMZ-std_' + datetime.date.today().strftime('%Y%m%d')
    if not a.no_deploy:
        m.ssh(f'mkdir -p {HW}/mgl {HW}/disks')
        m.put(a.rbf, f'{FAT}/_Computer/{rbf_name}.rbf')
    else:
        rbf_name = m.ssh(f'cd {FAT}/_Computer && ls SharpMZ-std_*.rbf | sort | tail -1', True).strip()[:-4]

    m.scan(f'{HW}/files', f'{HW}/disks', f'{HW}/mgl', f'{FAT}/config')
    for t in tests:
        remote = []
        for kind, index, src in t['files'] + [l[:3] for l in t['late']]:
            if src == 'gen:fd700':        # MZ-700 boot disk made from ramtest
                src = os.path.join(stage, 'fd700_ramtest.dsk')
                sh(f'python3 "{ROOT}/tools/make_boot_disk.py" "{MZF}/ramtest.mzf" "{src}" > /dev/null')
            if src.startswith('qd:'):     # tape image -> Quick Disk
                mzt = src[3:]
                src = os.path.join(stage, f'{t["name"]}_{len(remote)}.qdf')
                sh(f'python3 "{ROOT}/tools/mzf2qdf.py" "{src}" "{mzt}" > /dev/null')
            if src == 'gen:td_basic':     # BASIC 1Z-013B, then a BASIC program (Rock Paper Scissors)
                src = os.path.join(stage, 'td_basic.mzt')
                open(src, 'wb').write(open(yb('BASIC', 'MZ-700', 'BASIC 1Z-013B.mzf'), 'rb').read() +
                                      open(yb('19xx', 'MZ-700', 'Rock Paper Scissors (19xx).mzf'), 'rb').read())
            if src == 'gen:zulpoko':      # MZ-5Z001 then Zulpoko (see Z01) as type 05 named AUTO RUN, so BASIC's boot loads it
                src = os.path.join(stage, 'zulpoko.mzt')
                b = open(f'{SW}/mz1500/5Z001.mzt', 'rb').read()
                b = b[:128 + (b[18] | b[19] << 8)]                 # the BASIC record only
                z = bytearray(open(yb(1987, 'MZ-1500', 'Zulpoko Daisakusen (1987)(TAS).mzt'), 'rb').read())
                z[0] = 5; z[1:18] = b'AUTO RUN\r' + bytes(8)
                open(src, 'wb').write(b + z)
            if src == 'gen:qdtape_zulpoko':   # MZ-5Z001's BASIC record, then Zulpoko as it is (type 02): a tape for the QD slot
                src = os.path.join(stage, 'qdtape_zulpoko.mzt')
                b = open(f'{SW}/mz1500/5Z001.mzt', 'rb').read()
                open(src, 'wb').write(b[:128 + (b[18] | b[19] << 8)] +
                                      open(yb(1987, 'MZ-1500', 'Zulpoko Daisakusen (1987)(TAS).mzt'), 'rb').read())
            if src == 'gen:mz2000_search':  # MZ-1Z002 BASIC (an MZF around the ROM dump), Piranha-kun, Explorer
                src = os.path.join(stage, 'mz2000_search.mzt')
                b = open(f'{SW}/rom-candidates/emuz2000_tf/emuz2000/MZ-1Z002.dat', 'rb').read()
                h = bytearray(128); h[0] = 1; n = b'MZ-1Z002\r'; h[1:1 + len(n)] = n
                for k in range(1 + len(n), 18):
                    h[k] = 0x0D
                h[18:20] = len(b).to_bytes(2, 'little')
                open(src, 'wb').write(bytes(h) + b +
                                      open(f'{SW}/mz2200/Piranha-Kun no Isshukan (1983)(Enix)(Atsushi Shirai) [CT].mzt', 'rb').read() +
                                      open(f'{SW}/mz2200/Explorer (1989)(Micom Basic)(Taka Yamashita) [CT].mzt', 'rb').read())
            if src == 'gen:blank144':     # blank CP/M 1.44 MB disk (tools/make_blank_dsk.py)
                src = os.path.join(stage, 'blank144.dsk')
                sh(f'python3 "{ROOT}/tools/make_blank_dsk.py" "{src}" 1440 > /dev/null')
            if src == 'gen:basic_mzt':    # BASIC 1Z-013B, then a BASIC program, back to back
                src = os.path.join(stage, 'basic_rps.mzt')
                open(src, 'wb').write(open(yb('BASIC', 'MZ-700', 'BASIC 1Z-013B.mzf'), 'rb').read() +
                                      open(yb('19xx', 'MZ-700', 'Rock Paper Scissors (19xx).mzf'), 'rb').read())
            if src == 'gen:qd_blank':     # unformatted Quick Disk
                src = os.path.join(stage, 'qd_blank.qdf')
                sh(f'python3 "{ROOT}/tools/make_blank_qd.py" "{src}" > /dev/null')
            if src == 'gen:qd_basic':     # MZ-1500 BASIC on a Quick Disk
                src = os.path.join(stage, 'qd_basic.qdf')
                sh(f'python3 "{ROOT}/tools/mzf2qdf.py" "{src}" "{SW}/mz1500/5Z001.mzt" > /dev/null')
            if not os.path.exists(src):
                sys.exit(f'{t["name"]}: missing {src}')
            ext = os.path.splitext(src)[1].lower()
            side = len(remote)
            dst = f'{HW}/{"disks" if kind == "s" and index > 0 else "files"}/{t["name"]}_{index}_{side}{ext}'
            m.ssh(f'mkdir -p "{os.path.dirname(dst)}"')
            m.put(src, dst)
            remote.append(dst)
        t['remote'] = remote              # this test's files on the MiSTer (for 'fetch')
        cfg = os.path.join(stage, f'{t["name"]}{CFG_VER}.CFG')
        open(cfg, 'wb').write(status_bytes(t['model'], t['opts']))
        m.put(cfg, f'{FAT}/config/{t["name"]}{CFG_VER}.CFG')
        path = os.path.join(stage, f'{t["name"]}.mgl')
        open(path, 'w').write(mgl(f'_Computer/{rbf_name}', t, remote))
        m.put(path, f'{HW}/mgl/{t["name"]}.mgl')

    if a.menu:
        stage_menu = os.path.join(stage, 'menu')
        os.makedirs(stage_menu, exist_ok=True)
        m.ssh(f'mkdir -p "{MENU}" {AUTOTYPE} && rm -f "{MENU}"/*.mgl')
        for t in tests:
            name = menu_name(t)
            local = os.path.join(stage_menu, name)
            shutil.copyfile(os.path.join(stage, t["name"] + ".mgl"), local)
            m.put(local, f'{MENU}/{name}')
            steps = os.path.join(stage_menu, t['name'] + '.steps')
            open(steps, 'w').write(steps_file(t))
            m.put(steps, f'{AUTOTYPE}/{t["name"]}.steps')
            print(f'   {name}')
        m.ssh(f'python3 {Mister.KEYS_TOOL} watch-start')
        print(f'{len(tests)} tests in {MENU} (MiSTer main menu); the autotype watcher is running: a test picked '
              f'there types its keys and saves its screenshots in /media/fat/screenshots.')
        return

    refs = json.load(open(REFS)) if os.path.exists(REFS) else {}
    results = []
    for t in tests:
        print(f'{t["name"]} {t["model"]}: {t["desc"]}', flush=True)
        m.ssh(f'rm -f {FAT}/screenshots/{t["name"]}_*.png')
        if ('capture', 'start') in t['steps']:   # listen on the UART before the core (and the program) starts
            m.ssh('killall cat 2>/dev/null; stty -F /dev/ttyS1 9600 raw -echo; '
                  '(nohup cat /dev/ttyS1 > /tmp/prn_capture.bin 2>/dev/null &); true')
        m.cmd(f'load_core {HW}/mgl/{t["name"]}.mgl')
        time.sleep(4 + 2 * len(t['files']) + (2 if t['reset'] else 0))
        shots = []
        steps = t['steps']
        for i, (op, arg) in enumerate(steps):
            if op == 'wait':
                # A wait right before a screenshot ends when the screen matches that screenshot from a good run.
                nxt = steps[i + 1] if i + 1 < len(steps) else None
                ref = refs.get(f'{t["name"]}_{nxt[1]}') if nxt and nxt[0] == 'shot' and not a.no_refs else None
                ref = [ref] if isinstance(ref, str) else ref
                m.wait_for(arg, ref)
            elif op == 'type':
                m.type(arg)
            elif op == 'keys':            # raw key codes / chords, e.g. 29+56+100 (LCtrl+LAlt+RAlt: MiSTer's reset)
                m.ssh(f'python3 {Mister.KEYS_TOOL} key {arg}')
                time.sleep(1)
            elif op == 'pctype':
                codes = [PCKEYS[c] for c in arg.upper()]
                m.ssh(f'python3 {Mister.KEYS_TOOL} key ' + ' '.join(codes))
                time.sleep(sum(0.55 if '+' in k else 0.25 for k in codes))   # the daemon types after we return
            elif op == 'fetch':           # copy a mounted image back (after the core wrote to it); list a Quick Disk's blocks
                local = os.path.join(a.out, f'{t["name"]}_{os.path.basename(t["remote"][arg])}')
                subprocess.run(['scp', '-q'] + SSH_OPTS + [f'{m.target}:{t["remote"][arg]}', local], check=True)
                if local.lower().endswith('.qdf'):
                    subprocess.run(['python3', os.path.join(ROOT, 'tools/qdinfo.py'), local])
                else:
                    print(f'   fetched {local}')
            elif op == 'joy':               # hold these pad buttons (empty: release)
                m.ssh(f'python3 {Mister.KEYS_TOOL} joy {arg}')
            elif op == 'capture':           # printer UART: 'start' listens on /dev/ttyS1, then compare with the sim
                if arg == 'start':
                    pass                  # started before load_core (see above)
                elif arg == 'show':     # print what arrived (no reference)
                    got = m.ssh('killall cat 2>/dev/null; cat /tmp/prn_capture.bin', True)
                    print('   printer bytes: ' + repr(got))
                    results.append((t['name'], 'printer bytes: ' + repr(got)[:200], '', True))
                else:
                    got = m.ssh('killall cat 2>/dev/null; xxd -p /tmp/prn_capture.bin', True).replace('\n', '')
                    want = open(os.path.join(ROOT, f'verilator/tests/expected/{arg}.txt')).read().replace('\n', '')
                    ok = got == want
                    print(f'   printer bytes {"match" if ok else "DIFFER"} {arg}' + ('' if ok else f'\n     got  {got}\n     want {want}'))
                    results.append((t['name'], f'printer bytes vs {arg}: {"match" if ok else "DIFFER"}', '', ok))
            elif op == 'audio':             # record the HDMI audio from the capture card (on CAPTURE_HOST) for 4 s
                wav = f'/tmp/{t["name"]}_{arg}.wav'
                subprocess.run(['ssh', CAPTURE_HOST, f'arecord -q -D {CAPTURE_PCM} -f S16_LE -c 2 -r 48000 -d 4 {wav}'],
                               check=True)
                local = os.path.join(a.out, 'shots', os.path.basename(wav))
                os.makedirs(os.path.dirname(local), exist_ok=True)
                subprocess.run(['scp', '-q', f'{CAPTURE_HOST}:{wav}', local], check=True)
                lvl = subprocess.run(['python3', os.path.join(ROOT, 'verilator/tests/wav_stereo.py'), local, '0.5', '3'],
                                     capture_output=True, text=True).stdout.strip()
                print(f'   audio {arg}: {lvl} (Hz, peak-to-peak of 65536)')
                results.append((t['name'], f'audio {arg}: {lvl}', '', True))
            elif op == 'shot':
                m.cmd(f'screenshot {t["name"]}_{arg}.png')
                time.sleep(1.5)
                shots.append(f'{t["name"]}_{arg}.png')
        d = os.path.join(a.out, 'shots')
        os.makedirs(d, exist_ok=True)
        for s in shots:
            r = subprocess.run(['scp', '-q'] + SSH_OPTS + [f'{m.target}:{FAT}/screenshots/{s}', f'{d}/{s}'])
            results.append((t['name'], t['desc'], s, r.returncode == 0))
            if a.update_refs and r.returncode == 0:   # add this picture to the known ones (keep up to 4 variants)
                known = refs.get(s[:-4], [])
                known = [known] if isinstance(known, str) else known
                h = md5(f'{d}/{s}')
                if h not in known:
                    refs[s[:-4]] = (known + [h])[-4:]
            print(f'   {s}: {"ok" if r.returncode == 0 else "MISSING"}', flush=True)

    if a.update_refs:
        json.dump(refs, open(REFS, 'w'), indent=1, sort_keys=True)
        print(f'{len(refs)} reference screenshots in {REFS}')
    with open(os.path.join(a.out, 'index.html'), 'w') as f:
        f.write('<!doctype html><meta charset="utf-8"><title>SharpMZ hardware tests</title>'
                '<style>body{font:14px sans-serif;background:#222;color:#ddd}img{width:480px;image-rendering:pixelated}'
                'div{display:inline-block;margin:8px;vertical-align:top;width:480px}</style>\n')
        for name, desc, s, ok in results:
            if not s:                                     # a check without a picture (printer bytes)
                f.write(f'<div><b>{name}</b><br>{desc}</div>\n')
                continue
            f.write(f'<div><b>{s}</b><br>{desc}<br>' + (f'<img src="shots/{s}">' if ok else 'missing') + '</div>\n')
    print(f'{a.out}/index.html')


if __name__ == '__main__':
    main()
