# Software triage against mz800emu

`tools/triage.py` runs each single-file machine-code program of the year-based collection
(`software/Year-Based Collection of Games for the Sharp MZ-80K Line of Home Computers v1.0`, folders named
`MZ-700` / `MZ-800`) two ways and takes one screenshot of each, about 400 frames (8 s) after the program starts:

- the core: the half-clock Verilator sim (`verilator/obj_dir_fast/Vtop`, `make fast`), the program loaded straight into
  RAM and started with the monitor's `J` (MZ-800: `M` at the IPL first);
- the reference: mz800emu's headless mode with its own direct load.

```sh
cd verilator && make fast && cd ..
python3 tools/triage.py mz700 "software/Year-Based Collection ..." --jobs 10 --frames 400
```

It writes `verilator/out/triage/<model>/`: `NNNN_core.png`, `NNNN_emu.png`, `results.csv` and contact sheets
(`sheet_NN.png`, core left, emulator right; needs Pillow). Multi-file titles (Loader + Program) and BASIC programs
(types 02 and 05) are listed as skipped: they need the tape path or the BASIC interpreter.

The two runs don't start at the same cycle, so animation phase, attract-mode progress, colour cycling and anything
random differ; the sheets are reviewed by eye.

## MZ-700 (2026-10-04): 224 titles

| Result | Titles |
|---|---|
| Same screen | 165 |
| Differ only by timing, animation, colour cycling | 45 |
| Core bug, fixed | 2 (Base Zero, Revers [a1]) |
| Random colours (`LD A,R`), not a bug | 3 (Zaxxon, Blast Off, Maze Minder [b]) |
| Need more than a direct load | 6 (data files, loaders for a next tape file) |
| No usable reference | 3 (mz800emu gave no picture or an error; the core's screen is plausible) |

**Fixed: the 8253 interrupt storm.** Base Zero and Revers [a1] stayed at the monitor. They execute `EI`; the MZ-700
monitor enables the 8253 counter 2 interrupt (8255 PC2) at cold start but never programs counter 2, and our 8253
reset every counter to mode 2 with OUT high, so the interrupt never cleared (2,846 interrupts in 10 frames). The
counters now power up in mode 0 with OUT low and idle until a count is written, as mz800emu
(`rtl/i8254/i8254_counter.vhd`). This hit any MZ-700 program that enables interrupts without setting the clock.

**Not bugs:**
- Zaxxon, Blast Off and Maze Minder pick colours from the Z80 R register (Maze Minder's colour RAM fill is
  `POKE P, 70h + RND`), so they differ with timing.
- Destructeurs and Mental Mike (Loader) load their next part from tape; mz800emu shows `PLAY`, the core waits
  silently, because the OSD tape buttons default to Auto, which reports PLAY pressed so SAVE needs no prompt.

## MZ-800 (2026-10-04): 114 titles

| Result | Titles |
|---|---|
| Same screen | 72 |
| Differ only by timing, animation, border, palette shade | 8 |
| Core bug, fixed | 10 (black drawn grey in MZ-700 mode) |
| Header area wiped by the direct-load reset; fixed by Load Direct: Start Program (see below) | 12 |
| Cause not known yet | 0: Space Guerilla fixed with the 12, Planetoids by the palette reset, Abu Simbel by the 16-colour search read; Antiriad (Eng) is an mz800emu artefact (below) |
| Both blank, no usable reference, or not runnable this way | 8 |

**Fixed: black drawn as grey on the MZ-800 in MZ-700 mode.** The palette index for 700 mode was `1111 & '1' & GRB`,
so MZ-700 black became MZ-800 colour 8 (grey). mz800emu maps the MZ-700 colours to `{0, 9..15}`: black stays black
and colours 1-7 take the bright half. `VideoController.vhd` now sets the intensity bit to `G or R or B`. Ground
Attack, Moty, James, Space Duel, HOBRA-Schach, Hell Diver, IS-Chess, Life, Points and Starkiller now match.

**Load Direct and the MZF header.** A direct load holds the machine in a warm reset (`SharpMZ.sv`, as on hardware),
so the MZ-800 IPL runs afterwards and clears 10F0-11FF, where the MZF header was put. Programs that start in that
area or read their own header there (Exploding Fist, Jumpin' Jack, Tetris, Solomon's Key, Brouk, Jack the Nipper,
...) failed after Load Direct; mz800emu with the header zeroed fails the same way. From tape they load normally.

**Fixed (2026-10-05): Load Direct starts the program.** `rtl/direct_start.sv` keeps what the load writes to
10F0-11FF, lets the machine boot for about 1.5 s, writes those bytes back and feeds the CPU `DI`, the bank switches
the program needs (MZ-800: `IN (E1)` and `OUT (E3)`, CG ROM and VRAM out; `OUT (E0)` when it loads below 1000),
`LD SP,10F0` and `JP exec`, as mz800emu's bootstrap does. Only MZF type 01 is started. Rerun with
`tools/triage.py mz800 DIR --direct-start --only 25,35,42,43,45,51,54,56,57,65,72,83,103`: all 12 match, and so does
Space Guerilla (it loads at 11D0, inside the area the boot used). Pool and Moty differ only by the border (the
MZ-800 Border option is off in the sim).

**Fixed (2026-10-05): MZ-800 palette at reset.** Planetoids v3.1 sets only palette 0 (`OUT (F0),00`) and draws
with colours 1-3. `VideoController.vhd` reset all four palette registers to 0, so it drew black on black. They now
reset to mz800emu's power-on values (`gdg_init`: 9, F, 9, F) and Planetoids shows its instructions screen as in
mz800emu. 
**Fixed (2026-10-06): colour search reads in 16-colour mode.** Abu Simbel clears VRAM by writing 00 to 8000 and
copying it on with LDIR, reading through RF=8C (search for colour 1100, frame bit 0) in 320x200 16-colour mode.
mz800emu compares all four planes when the display is in 16 colours, whatever the RF frame bit; the core compared
planes I/II only, so every read matched and returned FF, which filled VRAM with stripes and wiped every other title
character. `VideoController.vhd` now takes the 16-colour compare first; new test `gfxrw16` (matches mz800emu).

**Antiriad (Eng): an mz800emu artefact, not a core bug.** Its music plays a note per /VBLN interrupt (Z80 PIO port
A bit 5, IM 2) in a handler that runs about two frames and re-enables interrupts before its RETI; the title
reaches its credits only when a note ends just before a vblank. The handler's keyboard check strobes row 10
(OUT D0,0A). On the MZ-800 the row decoder selects nothing for 10-15, so PB reads FF (the core). mz800emu maps
rows 10-15 to `keyboard_matrix[10]`, one past its 10-entry array ("TODO: overit na skutecnem HW"), reads a non-FF
byte and takes a shorter path: about 640 T-states less per note, which moves the note ends against vblank so
that one escapes at frame 127. Needs a look on a real MZ-800. Two changes came out of this, both matching the
real chips and mz800emu: the MZ-800 Z80 PIO now keeps an acknowledged port in service until RETI (a port in
service and port B don't request; an edge in service stays pending), and Load Direct starts the program at the
start of vblank (a fixed phase, as mz800emu's start at a frame boundary).

The reviews are in `verilator/out/triage/<model>/review.md` (not in git; rerun the script to rebuild them).
