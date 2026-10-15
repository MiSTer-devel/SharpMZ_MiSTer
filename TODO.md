# SharpMZ standard core: status and TODO

Goal: SharpMZ as a normal MiSTer 8-bit computer core. It has a stock `sys/`, one PLL, clock enables in place of derived clocks, native video through the framework scaler, and standard hps_io files. Main_MiSTer needs no Sharp-specific support. Branch `standard-core` on `alanswx/SharpMZ_MiSTer`.

Design notes are in `docs/design.md`, and the simulation and tests in `verilator/README.md`.

## Status

| Area | State |
|---|---|
| Framework | Done. Stock Template_MiSTer `sys/`, core type 0xA4, standard CONF_STR and hps_io with image slots S0 (tape) and S1/S2 (floppy). Main's `support/sharpmz` (0xA7) is unused. The tape and floppy entries are on the OSD's first page so MGL files can load them. |
| Clocks | Done. One 70.9376 MHz clk_sys with accumulator clock enables (`rtl/clkgen.vhd`); no signal-as-clock logic. Turbo is capped at clk_sys/2. |
| Video | Done. The author's v2 VideoController on clk_sys (`rtl/vc/`), native timing only (MZ-700/800 50 Hz, the others 60 Hz), scaled by the framework. |
| Tape | Done. MZF to CMT, direct to RAM, and a Tape Image slot (`rtl/tape_image.sv`) that loads multi-program MZTs, saves into a blank image and does MZ-80B APSS. |
| MZ-80K/80C/1200/80A/700 | Working in simulation. On hardware: all boot; MZ-700 tape and floppy (`J F000`) work. |
| MZ-800 | Working in simulation against mz800emu: IPL, 9Z-504M monitor, memory map, MZ-700/800 modes, all graphics modes, PSG, Z80 PIO, tape, floppy and CP/M. 12 native games and 84 of 94 disk images match mz800emu. On hardware: graphics tests, games from tape images (Cauldron II, Cybernoid), CP/M games from disk. |
| MZ-1500 | New (from mz800emu's MZ-1500): 9Z-502M ROMs, PCG (3 planes, palette, priority), 2 PSGs in stereo, Z80 PIO, Quick Disk (`rtl/mz_qdisk.sv`, .qdf/.mzq, read and write). Boots to the IPL and loads Lode Runner from Quick Disk with its PCG title screen pixel-identical to mz1500emu. On hardware: Lode Runner, Nintendo Tennis, and two-sided Battle City, Grobda, Milky Way and Batten Tanuki (side B swapped by the MGL) reach their title or demo; MZ-5Z001 BASIC formats a Quick Disk, saves, loads and runs a program (W01); 8 Quick Disk titles archived as two tapes run from disks made by `tools/mzf2qdf.py` (G01-G08). |
| Floppy | MZ-700/800 interface (`rtl/mz_fdc.sv`) with two drives from Extended DSK images. CP/M 1.3, 1.4, 2.3 and 4.1 boot in simulation. MZ-700: the MZ-1E05 ROM at F000 comes with the interface; `J F000` boots a disk made by `tools/make_boot_disk.py`. MZ-80B: the IPL boots SB-6511 Disk BASIC and CP/M 2.2 from the idealine.info images. |
| MZ-80B | Boots the IPL; loads SB-5520 BASIC from a tape image and SB-6511 Disk BASIC / CP/M 2.2 from floppy (sim and hardware). |
| MZ-2000 | Real IPL (MAME mz20ipl.bin) and MZ-2000 character ROM with katakana (MAME font.bin, hand-made, BAD_DUMP). Loads Gang Man and Zero Fighter (colour) from tape and boots a TF-DOS D88 disk with Japanese text, in the sim and on hardware. |
| FPGA | Latest build (6e70d0e, clean) meets timing (core clock +2.1 ns): about 18,750 ALMs (45%), 74% of block memory bits (the RAM disk adds 64 KB). Built on cottageubuntu or locally in the Quartus container. Built on cottageubuntu (Quartus 17.0.2); always clean-build (`rm -rf db incremental_db`). |
| Sim = hardware | `rtl/sharpmz_top.sv` holds everything between hps_io and video_mixer, and both `SharpMZ.sv` and the sim (`verilator/sim.v`) use it. The sim takes the OSD status word (`--osd "Name=Value"`, by the CONF_STR names) and Main-style downloads. `tools/osd_sweep.py` runs every value of every OSD option; `tools/mister_test.py` names options the same way (`tools/sharpmz_osd.py`). |
| Regression | `make test`: 48 tests (boot, keyboard, MZ-800 graphics, tape, floppy, Quick Disk, printer, Load Direct, sound), some needing `software/` (see `verilator/README.md`). All pass. Hardware suite: `tools/mister_test.py`, MGL tests T01-T31, Q, B, C, W, G, H, K, V and L01-L12 (2026-10-08). Keys go through `tools/mister_keys.py`, a uinput keyboard kept on the SD card at `/media/fat/tools/` (no mrext needed). Builds: `misterubuntu` (~7 min) or the local Quartus container. |

## Open work

### Plan while away from the hardware (sim, local Quartus container, emulators)
In order; each result is checked on mister.local later.
1. [x] `--dump-mem` in the sim: the dump was right, the address was read as decimal (1200 = 04B0). A and L are hex now.
2. [x] Youkai Toubatsu Hidejirou (MZ-1500 QD, G18): works; **hold SPACE** for a second or two at "set side B". The game's INKEY (compiled BASIC, scanner at 033F) reads the keyboard once per pass of a loop with a 1.3 s delay (B238: 5 x 255 x 255 x 14 T) and reports only keys that were up at the previous read, so a tap is missed. In the sim (`--qd-swap 1500:sideB --type-rate 100:3`) side B loads and the game starts. To confirm on hardware.
3. [x] Puckn Boy (MZ-2000 tape), from MZ-1Z002 BASIC's monitor (`MON`, `L`, Return at FILE NAME, then `J9000`): the header took ~97 s to arrive. `cmt.vhd`'s block transmitter didn't stop with the tape: the IPL stops the deck during the backup copy of BASIC's 23 KB data, and the rest of that copy kept playing into the next record's leader. It now abandons the block when the tape stops (as the padding process does). In the sim at real tape speed the leader is 13.4M CPU cycles again (was 384M) and the header loads ~200 frames after PLAY. Affects any MZ-80B/2000 program loaded after another from a tape image. Sim: `--fast-tape-at` and transmitter state in `--verbose` (`[xmit]`).
4. [x] MZ-80B CP/M (DISK01) on the MZ-2000: not a core bug. CP/M runs (it sits in its keyboard scan) but its BIOS sets PIO A bits 7-6 = 11, which on the MZ-80B maps text VRAM at 5000 and on the MZ-2000 maps it at D000 (as MAME's mz2000). The BIOS writes its screen to 5000, plain RAM on the MZ-2000. Needs an MZ-2000 CP/M.
5. [ ] Triage the year-based collection (`tools/triage.py`, results in `docs/triage.md`):
   - [x] MZ-700: 224 single-file machine-code titles. 210 match mz800emu (165 the same, 45 differ only by timing, colour cycling or animation). Found and fixed: the 8253 interrupt storm (Base Zero, Revers [a1]). Zaxxon, Blast Off and Maze Minder differ in colours picked with `LD A,R` (random). Destructeurs / Mental Mike are loaders that need their next tape file.
   - [x] MZ-800: 114 titles. 80 match. Fixed: black drawn as grey in MZ-700 mode (10 titles). 12 fail only through Load Direct (below).
   - [x] MZ-800 unknowns: Space Guerilla (Load Direct), Planetoids (palette reset), Abu Simbel (16-colour colour-search read, test `gfxrw16`) fixed. Antiriad (Eng) is an mz800emu artefact (keyboard row 10 read past its array); the Z80 PIO now holds a port in service until RETI and Load Direct starts at vblank (`docs/triage.md`).
   - [ ] Antiriad (Eng) on a real MZ-800: does the title reach its credits? (The core stays on the noise band; mz800emu escapes only through its row-10 keyboard read.)
   - [x] Load Direct starts the program (`rtl/direct_start.sv`, OSD Tape > Load Direct: Start Program / Reset Only): after the boot it puts 10F0-11FF back, sets the banks and jumps to exec with SP=10F0. The 12 MZ-800 titles and Space Guerilla now match; `ds_mz700`/`ds_mz800` tests. Checked on MZ-80K, MZ-80A, MZ-700, MZ-800 (both modes) and MZ-1500 in the sim; needs a hardware check.
   - [x] BASIC programs (sample checked 2026-10-08)  (354 MZ-700 type 05, 413 MZ-80K/80A type 02) need the interpreter loaded first; multi-file titles (Loader + Program) need the tape path.
     Hardware (`tools/mister_test.py --basic 20`: the interpreter by Load Direct, the program as the tape image, LOAD, RUN): 60 random BASIC programs, 20 each for the MZ-700 (1Z-013B), MZ-80K (SP-5025) and MZ-80A (SA-5510); all 60 load and run (World Cup takes ~20 s to start). One run of Cosmic Zap showed the BASIC banner shifted 8 characters left and wrapped, with the typing lost; two reruns were fine, so not reproduced. Watch for it.
6. [x] Knight Lore and Exolon read the joystick in the sim (`--joy0`): Exolon (3 = Joystick I, 1 = start) moves the player; Knight Lore (2 = Joystick I, 0 = start; option byte 5BA4 = 02, stick read at D047: OUT D0,07 then IN F0) turns Sabreman. Knight Lore's menu ignores keys while its 20 s title tune plays (only keyboard row 0 is read then), so press 2 and 0 after the tune. To try with a real stick on hardware.
7. [x] 1.44 MB disk images. The CMT tape buffer moved to DDR3 (`rtl/tape_ddr.sv`, 64 M10K freed; 521/553 used), `wd1793.sv` takes 21-bit image offsets and 4,096 sectors, and latches the image size at mount (the shared img_size bus changed under the scanner when another drive was mounted, so later tracks were missing). OSD Floppy > Drive B Unit puts the drive B slot on unit 2, CP/M 4.1's 1440K drive C:. In the sim CP/M 4.1 SAVEs to and DIRs C: on a blank (E5) 1.44 MB disk; `fdd_hd` writes and reads back a sector 1.45 MB in. The `_Vzor` templates are MS-DOS formatted, which CP/M's 1440K drive reports as full: use an E5-filled image (`tools/make_blank_dsk.py OUT.dsk 1440`). To try on hardware.
8. [x] Unit testbenches: `make test-i8254` (power-up quiet, mode 0 terminal count and rewrite, counter latch, modes 2 and 3; fails on the old mode-2 reset) and `make test-cmt` (header and data play back byte for byte; the record survives a deck stop after the header and in the data gap). The CMT testbench found PLAY_READY_SET_CNT counting past its range (harmless in hardware, fixed).
9. [x] Printer (OSD Printer: UART, `rtl/mz_printer.sv`): MZ-700 FE/FF and MZ-800/1500 PIO, byte taken on the RDP rising edge, RDA echoes RDP (busy while the 512-byte queue is full), sent 8N1 at Main's UART speed. In the sim, prntest.mzf (MZ-700 and MZ-800) and MZ-700 BASIC `LIST/P` print; `mister_printerd -m epson` turns the capture into a PDF with the text. To try on hardware with the daemon.
   - [x] MZ-700 BASIC `PRINT/P "..."` after `LIST/P`: prints on hardware (test P03 captures `10 REM TEST` then `HELLO` from the UART); the sim run had lost the typing.
   - [x] Sharp character set: OSD Printer Charset: ASCII converts Sharp lowercase and symbols to ASCII (graphics to spaces) and adds LF after a bare CR (`mz_printer.sv`, test `prn_ascii_mz700`). The core's Sharp/ASCII table (`ascii_conv.mif`, also used by Sharp ASCII Name for tape names) had `g` and `_` as spaces and ASCII `x` as Sharp `h`; fixed to mz800emu's table. Checked on hardware through /dev/ttyS1 (P02).
   - [x] Daemon test streams in `verilator/tests/printer/` (hello world, pen test, plotter demo, captured from MZ-800 BASIC with mz800emu `--printer`). The daemon's `sharpmz` model takes CR as a new line (with `-m epson` the lines overprint).
   - [x] MZ-1P01 / MZ-1P16 plotter: the daemon's `sharpmz` model draws the commands (MZ-700 owner's manual A.6) as vectors into the PDF, auto-selected for the SharpMZ core; regression and firmware comparison tests in printeremulation (local commit 1320354, not pushed). Check on hardware.
10. [x] Tester pack `out/SharpMZ-tester-pack-20261004.zip`: newest core, Knight Lore / Exolon tapes, Youkai, the triage fixes (Base Zero, Revers, MZ-700-mode black), printer test.

Waiting for the hardware: the scandoubler on a CRT and a VGA monitor; Knight Lore and Exolon with a real joystick; Tape Sound by ear; hardware runs of whatever 1-7 fix.

### Tester reports 2026-10-14 (Danjuro, EeDee; on SharpMZ_20261014)
Region Japan works for the testers' games. EeDee: replacement ROMs persist but "only for one machine at a time";
MZ-80B/2000 and MZ-80A floppies work; the tape image is "a different beast"; OSD Reset works; some MZ-1500 Quick
Disks load and some don't (21 images in ~/Downloads/qd.zip).

Reference checks: mz800emu's headless mode now takes `--qd FILE` and `--qd-swap FRAME:FILE` (refs/mz800emu, ours);
`.qdf` images go through `tools/qdf2mzq.py`. `mister_test.py --sweep MZ1500 3 WAIT GLOB` presses Q at the IPL.

1. [x] Tiny Xevious panel: the game prints through the monitor (CALL 0015); with the Japanese monitor 1Z-009B it reads
   "tiny XEVIOUS mz-700 / (c)namco / By.K.F." (sim). OSD "Region: Europe / Japan" (status 56) replaces MZ-700 Char
   Set: on the MZ-700, Japan is the Japanese CG (bank Ah), monitor 1Z-009B (banks 34h/35h, MZ700J_1Z009B.rom from
   idealine's 1z-009b.zip; the MZ-1500 monitor is the same ROM with reset to the IPL), and 60 Hz. Changing it resets.
   Sim: boot_mz700j (1Z-009B; 59072 cycles a frame = 60.04 Hz, against 70887 = 50.04 Hz).
2. [x] 60 Hz: the MZ-1500 and the Japanese MZ-700 use the 60 Hz colour timing (568 x 260, 15.6 kHz); European
   MZ-700/800 stay 50 Hz.
   - [ ] On hardware: timing, picture, and that games run at their original speed.
3. [ ] MZ-1500 sound. Measured: the sim (new `--wav-out`: the core's final stereo output) and the hardware (capture
   card, `('audio', label)` steps; mister126 needed `dvi_mode=0` in MiSTer.ini, backup MiSTer.ini.bak_dvi, and the
   card's "Digital In" capture switched on) both give left 440 Hz / right 880 Hz for tests/mz1500/psgstereo.mzf
   (test A01, sim psg_mz1500): the stereo works. The level was 4095 of 65535 peak to peak for one channel at full
   volume (1/16 of full scale). Now 3x on the MZ-800/1500 (PSGs and beeper): 12285.
   - [ ] "Left only" in some games: ask Danjuro which games (the ones that show "Stereo sound!").
   - [ ] Hardware level check of the new build (A01).
4. [x] Load Tape to CMT removed from the OSD (Tape Image does it all). The core still takes file index 1 (the sim's
   `--mzf` uses it). T07 and Z02 use the tape image.
5. [x] Tapes in the Quick Disk slot: S3 takes .mzt/.mzf; mz_qdisk shows the tape as the disk tools/mzf2qdf.py makes
   (byte-identical stream: tests/qd_tape, a testbench of mz_qdisk, run by run_tests.sh). Read only. Tape message
   "QD:" (in place of "TAPE") for an MZ-5Z001 Quick Disk BASIC file (type 02 at A215) on an MZ-1500 tape. Hardware: N01-N05 (tapes
   mounted as the QD), Z04 (MZ-5Z001 + Zulpoko as one tape in the QD slot, LOAD, RUN).
   - Door Door and the other two-tape titles: side A from the tape image, side B mounted as the Quick Disk.
   - Bacterianns, Zulpoko, Techno City Cars: BASIC from its disk or tape, then the program's tape in the QD slot, LOAD.
6. [x] Batten Tanuki (QD): F-keys did nothing. The game scans the keyboard in a Z80 PIO interrupt (IM 2, PIO port A
   bit 4 = the 8253's OUT0, active high) taken at each terminal count of counter 0 (mode 0, reloaded by the handler).
   The core, like mz800emu, gave the PIO the inverse of OUT0 (the MZ-800's /CTC0): one interrupt, then none. On the
   MZ-1500 PA4 is now OUT0 itself (mz80c.vhd); the MZ-800 keeps the inverse. tests/mz1500/pioint.mzf (sim
   pio_mz1500): 3785 interrupts by frame 300 (was 1; mz800emu gives 1). Hardware Q06: F1 starts the game.
   May also be behind Danjuro's skipped keys and some sound on other MZ-1500 titles: retest those.
7. [x] 3-D Golf, Earthbound, Nobunaga no Yabou (and Zulpoko's "Illegal data error in 150"): fixed. On the MZ-1500,
   OUT E5 (open the CG/PCG window) also switched D000-FFFF from RAM to ROM in the core (mz80c.vhd, as mz800emu), so
   after OUT E6 a program that had mapped RAM with E1 found ROM there: Nobunaga's INPUT KNJ returned through its stack
   at FDxx into the ROM (F6DB) and the ROM's QD loader searched side A forever. In Takeda's EmuZ-1500 E5 only opens
   the window (it covers D000-EFFF, F000-FFFF empty) and E6/E4 close it; the bank choice is kept. Found by comparing
   CPU traces with the macOS port of CSCP (~/dev2/common_source_code, scripted mode added: --script, --qd,
   --qd-swap, --type, --screenshot, --dump-every, --trace-cpu). Also fixed on the way, as the Z80 SIO / EmuZ-1500:
   the QD SIO's 3-byte receive FIFO, a channel reset clears overrun, the head goes home at the end of the disk.
   mister126: Q07 Nobunaga title ("HIT ANY KEY"), Q08 Earthbound title, side B, part 1, Q09 3-D Golf title, side
   B, F1, the game; Z04 Zulpoko's title; no change to Q01-Q06, W01, C01-C03, N01.
   (The kanji ROM board was a wrong guess: the game never touches its ports. mz800emu stops earlier, on its PIO
   interrupts.)
8. [x] EeDee's 21 QD images (14 disks/side A) on mister126: every one ends where mz800emu ends. Run: Diamond Chase,
   Excite 4-nin Mahjong, Nonbarla Panic, Sonic Birds, Zexas. Ask for side B (correct): Dig Dug, New Rally-X, Flappy.
   "QD:File mode error": Cockpit and Sparrow are BASIC programs (type 02) on disks without BASIC: boot MZ-5Z001 first
   (now: its tape in the QD slot), then this disk, RUN"COCKPIT". T.N.T. Bomb Bomb loads its PCG data (slow).
9. [ ] Cybernoid (MZ-800, Profi, 4 files: loader 4F00, CYB1-3): a core bug. mz800emu (the four files as one tape, C at
   the IPL) shows the Cybernoid loading picture with a counter and reaches the game's menu at about frame 20000
   (real tape speed). On mister126 (H06 real speed, H07 Fastest, H08 VRAM Wait On) the picture comes out scrambled
   (the artwork's outline, garbled) and the counter stops at 979. The loader is packed (no plain ROM calls): likely
   its own tape routine, drawing while it loads, misreading bits. Next: CPU traces of the sim and mz800emu from the
   loader's start, first divergence (tape bit timing, wait states, the 8253/PIO it may use for timing).
10. [ ] EeDee: "ROMs persistent for one machine at a time": Load System ROM is one remembered file (FC) for the core,
   not per model. Explain; a per-model ROM would need one CONF_STR entry per model.
11. [ ] Tape image: EeDee is still working it out (item B): a README walkthrough.
12. [ ] Danjuro (later, with emulators): "a lot of games, even text adventures, had a sort of lag (sometimes key
   input would be skipped), which didn't happen in the emulators". Check on 20261014b (60 Hz MZ-1500): keyboard
   scan vs. PS/2 key timing (keymatrix hold, the PC layout's forced SHIFT lead/tail), with mister_keys typing fast.
   Lead: keymatrix's key hold keeps every pressed key in the matrix until 50 ms after the latest press, so two keys
   pressed within 50 ms are both down at once (the first even if already released); routines that ignore two keys
   down would skip one. Ask Danjuro for a title and test typing on hardware.
13. Danjuro's emulator notes: Tiny Xevious's side panel is right in the emulators (it is on 20261014b with Region
   Japan); MZ-800 was 50 Hz only (kept); Bacterianns fails there too; Door Door works; Batten Tanuki's F-keys work
   there (so item 6 is the core's: reproduced in the sim, F1 at the prompt changes nothing).

### Tester reports 2026-10-13 (on SharpMZ_20261012/12b)
Confirmed fixed by testers: replacement ROMs persist, MZ-80A floppy, OSD Reset. Tester 2 suspects their own MiSTer is faulty,
so their results need confirming here. Files from tester 3 are byte-identical to the year-based collection's copies.

**A. MZ-80B / MZ-2000 floppy hangs (EeDee): fixed (2026-10-13).** With OSD MZ-80B/2000 Boot Reset on, the IPL loaded the
boot program, then restarted for ever ("IPL is loading CP/M 2.2" flashing): `mz80b.vhd` held BOOTSTRAP_n (IPL ROM at 0000)
for as long as the option was on, so the IPL's switch to RAM (NST) never took. Boot Reset now acts only at a reset. Our
tests passed because they leave Boot Reset off; EeDee needs it on to get back to the IPL with a reset. The floppy
controller now also takes the machine's warm reset, as the real interface does (it had only the core's cold reset).
On hardware: F03 (MZ-80B, disk mounted at the IPL, reset boots CP/M 2.2, reset again boots it again), F04 (MZ-2000
TF-DOS the same way). Sim: `--fdd-frame N` (mount later), `--boot-reset`. Test tool: `--sweep MODEL SLOT WAIT GLOB`,
`('keys', '29+56+100')` steps. Fresh-core sweep of the idealine MZ-80B disks: DISK06 and DISK10 report "Repeated read
error" (check against MAME or their CRCs).
- [ ] Sim regression test for Boot Reset + disk (fdd_mz80b_br).
- [x] DISK06 / DISK10 read errors on the MZ-80B: bad dumps, not the core. Both images lack track 0 sector 19 (9 of the 10
      sectors; every other track and DISK05 have 10), and that sector holds system data on the other disks, so a real
      MZ-80B would report the same error. DISK06 also has a duplicate sector 11 on track 12 (harmless). No other copies
      in the collection.

**B. Tape Image is hard to follow (EeDee).** Already improved in 20261012b by Tape Messages (TAPE n/total NAME).
- [ ] Check with EeDee once on 12b; consider a README walkthrough (mount, C/L, how records advance, Rewind).

**C. MZ-1500 BASIC: "CMT: Illegal filemode error" at the end of loading BASIC; then LOAD fails (tester 3).**
BASIC mz-5z001.mzt (A216 bytes + a type 02 AUTO RUN record), Zulpoko Daisakusen and Techno City Cars (type 02, load A215).
MZ-5Z001 rejects type 02 in the core; patched to 05, Zulpoko stops at "Illegal data error in 150", as in mz1500emu (Z01).
But three files of the collection use 02 for MZ-5Z001 programs, so 02 may be right and something else is wrong.
- [x] mz1500emu with the unmodified BASIC tape: the same "CMT:Illegal filemode error" (on the type 02 AUTO RUN record).
      The core matches the reference: the tape images are wrong, not the core.
- [x] As a Quick Disk (`tools/mzf2qdf.py` with MZ-5Z001 + both programs, Q at the IPL): LOAD "ZULPOKO" and LOAD "TCCARS"
      work (no filemode error), so these are Quick Disk files (02 = BTX on QD) dumped to tape.
- [x] But neither runs: Zulpoko stops at "Illegal data error in 150" (as in mz1500emu with the type patched to 05);
      Techno City Cars clears the screen and ends at Ready. The dumps probably lack files the originals had on the disk
      (PCG data, machine code), or need another BASIC. mz1500emu hung loading TCCARS from a patched tape (inconclusive).
- [ ] Ask the tester for the original Quick Disk dumps (.qdf/.mzq) of these TAS titles.
- [ ] Planned (not started): detect type 02 records on the MZ-1500/800 when a tape is mounted and say so: a MiSTer info
      popup (CONF_STR `I,`, fixed text: "Quick Disk files on this tape; MZ-5Z001 can't load them from tape") and the
      overlay naming the record (`TAPE 2/3 ZULPOKO: QD FILE`). README note on `mzf2qdf.py`. Sim and hardware tests.
- [ ] Dark Storm - Demon Crystal III (type 01, sides A and B): C at the IPL with side A, then side B. Check it loads.

**D. MZ-1500 "didn't load anything" (tester 2).** Loads then nothing happens, or the machine resets.
- [ ] Ask for titles and how they were loaded (Tape Image / Load Direct / Start Direct, Fast Tape setting).
- [ ] Try Dark Storm and a few C01-C24 titles with each method; Load Direct on the MZ-1500 starts at the exec address
      without the IPL's setup (PCG, PSG, banks), so it may need the IPL path instead.

**E. Japanese MZ-700/800 programs: no Japanese character set (tester 2).** Japanese adventure games show garbage; the
Japanese MZ-700 has a CG ROM with katakana in place of the European lower case.
- [x] The MZ-1500's CG in the core is MAME's `mz700fon.jpn`, the Japanese MZ-700 font, already in the core's format
      (CG bank Ah). New OSD option MZ-700 Char Set: Europe / Japan selects it on the MZ-700 (status 56,
      CONFIG(CG_JAPAN)). Sim: `--osd "MZ-700 Char Set=Japan"`. Hardware: X03 (Donkey Gorilla), X04 (Tiny Xevious).
- [ ] MZ-800 Japanese: its CG is read by the CPU from the MZ-800 system ROM (1000-1FFF) and copied by the IPL into the
      700-mode CG-RAM, so it needs a Japanese MZ-800 ROM image as well as a CG bank.
- [ ] MZ-80K Japanese CG (idealine `MZ80K2E Jap CG`, 2 KB): the CG ROM image is full (12 banks), so it needs extending.

**F. MZ-700 PCG (tester 2): "some games might use the PCG-8800".** Probably the HAL PCG-700, the MZ-700's PCG.
- [x] The core had its registers (E010 data, E011 address, E012 control: bits 0-1 address, 2 set, 3 display off,
      4 strobe, 5 copy from ROM; idealine pcg700_05) but never switched the display to the PCG RAM (E012 bit 3 was
      ignored) and wrote set 2 into set 1 on the MZ-700. Fixed in VideoController: with bit 3 low the upper 128
      characters of each set come from the PCG RAM. Off at reset. Sim test pcg700_mz700 (tests/mz700); hardware X02.
      mz800emu has no PCG-700, so the reference is the documentation.
- [ ] Try Mappy with its PCG data (Year-Based 1984) and PCG BASIC (idealine) on hardware.

**G. Graphics glitches on MZ-700 games (tester 2).**
- [x] Metro-Cross (a third of the screen on the left): the game reads E200-E2FF in play; the core applied the MZ-80A's
      hardware scroll (and E014/E015 display invert) on the MZ-700 too, which has neither. Now MZ-80A only. The
      title matches mz800emu. Sim test e2scroll_mz700; hardware X01. `--trace-io` also logs those E-page accesses.
- [x] Donkey Gorilla's garbled title and the odd text in Tiny Xevious and Metro-Cross ("(c) namco", "Arranged by
      Oh!mz") are Japanese-set text shown in the European set (mz800emu shows the same); with MZ-700 Char Set: Japan
      Donkey Gorilla's title is its Japanese instructions and the Namco texts read correctly (item E).
- [ ] Tiny Xevious's side panel in play (":TINY: XEVIO :MZ", "(:C:):NA") is the same in mz800emu and in both sets;
      ask the tester whether that is what they meant.

Working well for testers: Snake & Snake (MZ-700), Donkey Gorilla in play, MZ-80K/80A BASIC programs.

### Tester report 2026-10-12 (after the first release)
- [x] Replacement ROMs persist: Load System ROM and Load CGROM are remembered OSD files (`FC`), so Main reloads the last one at every core start, and the machine is held and reset while a ROM image loads, so it starts on it. `boot.rom` in games/SharpMZ loads too. On hardware: with 80ktc chosen once, the core starts in it ("System Monitor"). Found on the way: Load System RAM and Load CGROM wrote over the monitor ROM (Main gives every file address 0; the CONF_STR addresses only count in DDR); they now go to their own regions.
- [x] Tape position on screen (OSD Tape Messages, on by default): `rtl/tape_osd.sv` draws a line at the bottom of the picture for 150 frames when the tape image has a record ready (`TAPE 2/5 NAME`), reaches the end, saves or is full, in the MZ-700's characters (`tools/make_osd_font.py`). MiSTer's info popups (CONF_STR `I,`) only show fixed strings, so they can't name the program. On hardware: TAPE 1/2 S-BASIC on mounting, TAPE 2/2 R.P.S. once BASIC is in (L16). The first message comes a few seconds after the core starts, when the record has loaded.
- [x] MZ-80A floppy: its interface has the FDC at D8-DD as the MZ-700's, so mz_fdc now runs on the MZ-80A with its interface ROM at F000 (MZ80A_FDIF.rom, banks 1Ah-1Bh, `tools/patch_roms.py`). The ROM doesn't poll: its INI loop runs through an opcode fetch at F3FE (F7FE), and the interface holds the CPU in WAIT there while a command runs and no byte is ready (`mz_fdc` wait_req, `sharpmz.vhd`). `F` at the monitor, Return: SA-6510 Disk BASIC boots (sim test fdd_mz80a; hardware F02).
- [ ] MZ-80K floppy: a different interface (ports F8-FA, motor by IN (C), DRDY/CRDY/RQM flags; ROM and source in `software/idealine/mz-80k/mz80kfdif`), so it needs its own controller model. The old core never had it either.
- [ ] Load real tapes through MiSTer's audio input (upstream issue #7): the core leaves ADC_BUS unused; other cores feed the ADC's tape signal (sys/ltc2308) into their cassette input. Feed it to the CMT read bit.
- Already done in the release (the tester had an older build): OSD Reset works (fixed in 20261009b); floppies work on the MZ-700 (`J F000`), MZ-800, MZ-80B and MZ-2000 (mount, then reset).

### Next
- [ ] Sound tests for the other models: MZ-80K/80A note table (does the MZ-80K need the counter 0 divide-by-2?), MZ-800 PSG channels and noise, MZ-80B/2000 PC2.
- [x] Beeper vs PSG level: on the MZ-800/1500 the beeper is now one PSG channel's level, as mz800emu mixes them; full range on the models without a PSG.
- [ ] Tape saves into a growing image instead of a pre-made blank tape: needs a Main change, proposed in `docs/main-growable-images.md` (with an RTL-only alternative through Main's save files).
- [x] Astro1: the monitor bell when the game restarts the monitor now plays (880 Hz, frames 1049-1055 in the sim, as mz800emu). The E008 sound-gate write was lost at some CPU phases (fixed with the key-hold change).
- [x] Floppy writes: CP/M 4.1 SAVE 1 TEST.COM on hardware (W03); DIR lists it and the image fetched back has the directory entry.
- [ ] Floppy: drive B, writes at turbo speeds.
- [ ] 8253: the CP/M 1.x loader waits for counter 2's first clock (the first 1 s pulse of counter 1): about 1 s here, as the 8253 datasheet gives, and 2 s in mz800emu. Only the boot pause differs; confirm on hardware.

### MZ-800
- [x] Border colour: OSD Display > MZ-800 Border draws the BCOL colour around the picture (77/67 pixels left/right, 46/42 lines top/bottom in 320 mode, as mz800emu), 464 x 288 (928 x 288 in 640 mode) on hardware (T29-T31). Done after the video controller (`rtl/mz800_border.sv`), in the blanking, so the picture and the frame tests are unchanged.
- [x] Joysticks: ports F0/F1 read MiSTer joysticks 1/2 while 8255 PA4/PA5 strobe them, as the MZ-800 Technical Reference Manual gives (mz800emu's code uses PA5/PA6, one bit off from its comments; Exolon strobes PA4 only and saw nothing). Test joy_mz800. Knight Lore and Exolon have joystick options; to be tried on hardware.
- [x] Printer port: see plan item 9 (parallel, bridged to the MiSTer UART for `../printeremulation`).
- [x] RAM disk board: the 64 KB "standard" board of mz800emu (EA/EB, F8-FA; OSD MZ-800 RAM Disk). Not yet tried with CP/M; the Pezik boards (E8, EC-EF) and larger sizes aren't implemented.
- [x] 1.44 MB disk images: see plan item 7 (CP/M 4.1 drive C: on a blank E5 disk; the `_Vzor` templates are MS-DOS formatted).
- [x] MZ-800 tapes with exec 1108 (66 games): the header holds a relocating loader that reads the body with the ROM's tape routine, not a turbo format. Lunar Jetman, Three Weeks in Paradise, Silent Service, Boulder Dash III and Robocop 2 load on hardware (H01-H05). The other unusual header types are later parts of multi-part games.

### MZ-1500
- [x] Quick Disk writes: the SIO transmitter (break, data, CRC on underrun, sync) as the ROM drives it, written sectors back to the image. BASIC INIT "QD:", SAVE and LOAD work on hardware; images check with `tools/qdinfo.py`. Writing needs a full-size image (`tools/make_blank_qd.py`).
- [x] The two-tape "DATA" titles (Rally-X, Druaga, Dig Dug, Mappy, Door Door, Knither, Zolvass, Burnin' Rubber, ...) are Quick Disk products dumped to tape, not installers: side A asks for side B ("SET PROGRAM QD ?", answer Y). `tools/mzf2qdf.py` makes a disk of each side.
- [x] Fast tape 32x mapped to the normal CPU speed on the MZ-700/800/1500 and MZ-80B/2000; it now selects the fastest rate (capped at about 35 MHz). The 48 KB Druaga file loads in under a minute on hardware.
- [x] Short keypresses: a remote or scripted key (make and break back to back) was missed by the MZ-1500 IPL while it probes the Quick Disk. Every key now stays in the matrix until 50 ms after the latest press (`keymatrix.vhd`; 80 ms made the MZ-80K drop fast-typed keys). This exposed an old bug: the E008 sound gate latched only on the 2 MHz peripheral enable, so some CPU writes to it were lost (no beeper).
- [x] Tape titles on hardware: the C tests press `C` twice, and the 50 ms key hold catches mrext's short taps.
- [x] CG ROM read through OUT E5 0, with bit 7 as the left pixel like the PCG (software copies CG characters into the PCG; Xetter '91's text was mirrored with the ROM dump's order). Test cg_mz1500: 'F' reads 7E40407840404000.
- [x] Yakyu-kyou's tape ends on blue/green stripes, identical in mz1500emu: the program (or the dump), not the core.
- [x] Nonbarla Panic (PCG set + main) is a Quick Disk title too and runs from a converted disk (G17).
- [x] Youkai Toubatsu Hidejirou (G18): SPACE has to be held, the game polls the keyboard every 1.3 s (plan item 2).
- [x] Galaga's tape (GALAGA DATA + GALAGA MZ-1500) is a Quick Disk title: `mzf2qdf.py` puts both files on one disk and it plays (G09).
- [x] Joysticks: MZ-1X03 on E008 bits 1-4 (OSD MZ-1X03 Joysticks, also for the MZ-700): buttons during the picture, axis pulses of 68 + 28 x position T-states from the start of vertical blank, as mz800emu's joymz-1x03.c. Not yet tried with software.
- [x] MZ-1500 ROMs: identical to MAME's mz1500 set (9z-502m.rom, mz700fon.jpn).

### Other models
- [x] MZ-700 floppy on hardware (T08).
- [ ] MZ-2Z009 Disk BASIC (loads from tape) on a blank disk.
- [x] MZ-2000: MZ-80B CP/M (DISK01) stays black on the MZ-2000 because its BIOS is MZ-80B only (plan item 4).
- [ ] MZ-2000 character ROM is MAME's hand-made font.bin; a real dump of the IX0286PA (also the Japanese MZ-80B font) would replace it.
- [x] More MZ-2000 tapes (K01-K08): Itasandrias, Super Doors and Project A (its own loader reads a 37 KB DATA file) run; Explorer and Piranha-kun are BASIC programs (the IPL says "File mode error", as it should); the Flicky tape is only its loader. Ice Block's MZT is malformed.
- [x] Puckn Boy stays at "IPL is loading": it is a machine-code program for MZ-1Z002 BASIC, not an IPL tape (plan item 3).
- [ ] MZ-80B SB-7010 (DISK29) loads and stops at its monitor's `*` prompt; find out how FDOS is started from there.
- [x] wd1793: EDSK sectors dumped with a CRC error (ST2 bit 5 data field, ST1 bit 5 ID field) report CRC ERROR when the OSD Floppy CRC Errors is Report: at the end of the sector's data, ending a multi-sector read there (a WD179x checks the CRC after the data; flagging it at the ID broke reads force-interrupted before the bad sector). Default Ignore: DISK38 has sector 4 flagged on its boot tracks but good data, and boots; DISK37 gives the IPL's "Loading error" with Report and hung before.
- [ ] MZ-80K/80A floppy interface ROMs and the SA-6510 boot disk (`software/idealine/`).
- [ ] MZ-80B: GRAM and 40/80 column switching with real software; SAVE and APSS.
- [x] MZ-80K/80C/1200/80A keys: cursor keys, Backspace/Delete/Insert and Home/End go to the machine's UP/DOWN, RIGHT/LEFT, INST/DEL and CLR/HOME keys, with SHIFT where the monitor's key table needs it (SA-1510: unshifted UP; SP-1002: unshifted DOWN); MZ-80A/1200 keypad to its keypad (`tools/fix_keymap.py`). Tests kb_mz80k, kb_mz80a. The MZ-80A reads SHIFT late: a tap shorter than about 80 ms gives the unshifted key.
- [x] Dezeni Land (MZ-1500, Hudson): a tester saw "IPL is loading" hang; that screen is the MZ-80B/2000 IPL (wrong model). On the MZ-1500 (C at the IPL menu) Tape 1 loads, then N + Return at the QD question, and the title screen comes up (sim).
- [x] Alternative MZ-80K monitor ROM (a tester's 80ktc.rom): Load System ROM puts it over the 40-column monitor; it shows after an OSD Reset and stays until the core is reloaded. README section, `tools/make_monitor_rom.py` for the other models, sim `--load-rom`.
- [x] MZ-80K 3-D Maze "garbled": mz-archive's Tests/3-D MAZE.MZF is the MZ-80A program (SA-5510 BASIC). Each version on its own machine and BASIC runs correctly on hardware (tests M01, M02).

### Core and polish
- [x] Audio mixing: OSD Tape Sound mixes the tape signal in quietly while it moves. Not yet heard on hardware.
- [x] Joystick mapping in the OSD (Fire 1, Fire 2).
- [x] Analog video: native 15.6 kHz on every model; video_mixer adds the 31 kHz scandoubler (MiSTer.ini forced_scandoubler, OSD Scandoubler Fx with HQ2x and scanlines). The MZ-80K/80A/80B 60 Hz modes now use clk_sys / 8 (/ 4) pixel clocks with a 568 (1136) pixel line, like the MZ-700: their 8/16 MHz enables were uneven and the scandoubler cut lines short. Checked through the scaler on hardware (V01-V05); not yet seen on a real CRT or VGA monitor.
- [ ] Show tape status (record number, tape full) in the OSD.
- [x] Tape PLAY_READY delay: half a second of clk_sys (`CLK_SYS_HZ` in clkgen_pkg), was a bare 32,000,000.
- [ ] Optional 64 MHz clock for the MZ-80K/80A/80B family, so their clock enables are exact (±1 clk_sys jitter now).
- [x] Unit testbenches for `cmt.vhd` and the i8254 (`make test-cmt`, `make test-i8254`).
- [x] WAV to MZF converter: `tools/wav2mzf.py` (WAV, or FLAC etc. through ffmpeg; either polarity; header and body copies). Decodes the No-Intro MZ-700 "BASIC" and "Applications" recordings.
- [x] Tester build `releases/SharpMZ_20261006.rbf` (Load Direct start, MZ-800 palette reset, alternative monitor ROMs, MZ-80B/2000 tape fix). From now on each tested build goes in `releases/` with its date.
- [x] Printer on hardware: the core's UART is the MiSTer's /dev/ttyS1, so tests P01/P02 capture it there; the bytes match the sim exactly, Sharp and ASCII charset (2026-10-08). The daemon's PDF output on the MiSTer is still to try (no daemon installed there).
- [x] 1.44 MB disk as CP/M 4.1's drive C: on hardware (test F01, Drive B Unit: 3rd): DIR C:, SAVE 1 C:TEST.COM, DIR C: lists it; the fetched image has the directory entry (2026-10-08).
- [x] MZ-2000 BASIC `LOAD "NAME"` on a tape image with several programs (test K09: MZ-1Z002 BASIC, Piranha-kun, Explorer): BASIC found Piranha-kun's header, kept the tape running and waited for ever, because the tape image only moved on when the motor stopped or on an APSS seek. `cmt.vhd`: a record that finishes with the motor still on is released as on a motor stop, and the next record, once the tape image has loaded it, plays from its gap, as on a real tape. On hardware: FOUND (Piranha-kun), FOUND "EXPLORER", LOADING "EXPLORER", Ready.
- [x] MZ-800 joystick on hardware (test J01, a virtual Xbox 360 pad from `mister_keys.py joy`): right + fire 1 gives E7 FF E7 FF, as the sim. Fire 1 is the pad's east button (B on an Xbox pad, MiSTer's SNES layout).
- [x] OSD Reset and Reset and close OSD did nothing on any model (tester, also on the old core). The joystick entries (`J1`, `jn`) came before them in CONF_STR, and Main expects them after every menu entry (the user spotted this); moved to the end. The reset request is also stretched to about 1 ms so the reset one-shot always sees it. On hardware: OSD Reset clears the MZ-700 monitor screen (2026-10-09). The MiSTer's physical reset button is a cold reset; its USER button and LCtrl+LAlt+RAlt are warm resets.
- [x] OSD Tape Image Start: Direct (2026-10-11): on mounting, the tape image's first program goes into RAM and starts as Load Direct does (`tape_image.sv` writes it, the machine held in reset, `direct_start.sv` starts it) and the tape is left at the second program. On hardware: L13 (MZ-700 BASIC starts by itself, LOAD gets the program), L14 Exolon and L15 Knight Lore (MZ-800 loading screen, then the game from the tape). Sim test tape_direct. Experimental: roll back if it causes trouble.
- [x] OSD Keyboard Layout (2026-10-11), PC by default: each key types its US PC legend on every model. The keymap has PC tables for the PC's SHIFT up and down (`tools/fix_keymap.py`), made from what each model's monitor or BASIC shows for every key in the sim (`tools/keymap_measure.py`, `tools/keymap_pc_chars.json`; mz800emu's table fills in the MZ-700/800). `keymatrix.vhd` forces the machine's SHIFT for a key that needs another one: the SHIFT changes 40 ms before the key reaches the matrix and stays 100 ms after it is released (the MZ-80K/80A monitors take SHIFT from an earlier scan than the key). On hardware (K11-K13): the MZ-80A and MZ-700 type every punctuation character they have, the MZ-80K its own. Characters a model doesn't have type nothing (MZ-80K: `:<>?@[\]^_` and the rest; MZ-700/800: `|`; MZ-80B/2000: `?\|`, no key typed them in BASIC, SHIFT / is a graphic, 84). Sharp keeps the old layout by position (the hardware tests use it). Sim tests kb_pc_mz80a, kb_pc_mz700; `keymap_measure.py --verify` types every character on every model.
- [ ] MZ-80B/2000 PC layout: find where `?` is on their keyboards (no measured key types 3F; maybe a GRAPH or kana combination) and check the layout on hardware.
- [x] MZ-1200 keyboard: it runs SP-1002, the MZ-80K monitor, but had the MZ-80A keymap, so no key typed what it said (as in the upstream core). It has the MZ-80K bank now (K14 on hardware).
- [x] MZ-80A/MZ-1200 keys (2026-10-10): Ctrl typed 4 (the bank had Ctrl on F2 bit 7, the 4 key); right Shift pressed CTL. Now Ctrl is CTL (F0 bit 7), Esc is BREAK (shift CTL), right Shift is SHIFT and Alt is GRPH (`tools/fix_keymap.py`). On hardware: A Ctrl B types AB, Esc breaks out of LOAD. The punctuation keys follow the MZ-80A's own legends and positions, not the PC's.
- [x] MZ-1500 tester reports (2026-10-09). Maze Land (Enix) loads by Tape Image, Load Tape to CMT (C at the IPL, Z02) and Load Direct (Z03) on hardware. A Z02 failure was the test's own 60 ms key press, which the 9Z-502M IPL's debounce ignores; `mister_keys.py` now holds keys 120 ms. Zulpoko Daisakusen is a BASIC program, not a standalone game: its header says type 02, which MZ-5Z001 rejects as an illegal filemode (probably a Quick Disk file type kept in the tape conversion); as type 05 it loads and stops at "Illegal data error in 150", the same in mz1500emu (Z01), so the file needs another BASIC or is damaged. Load Direct jumps to its exec address 0000, hence the garbled screen.
- [ ] Hardware check of the newer features still only tested in the sim: the daemon's plotter model on the MiSTer, Knight Lore and Exolon with a real pad, MZ-80B/2000 APSS with real software. (Load Direct on every model and Puckn Boy after BASIC passed on hardware 2026-10-08.)
- [x] Hardware run 2026-10-08 (MiSTer, `tools/mister_test.py` L01-L12): Load Direct starts programs on the MZ-800 (Jumpin' Jack, Exploding Fist, Solomon's Key), MZ-700, MZ-80K and MZ-80A; Abu Simbel and Planetoids fixed; Puckn Boy after MZ-1Z002 BASIC; Dezeni Land (MZ-1500); Antiriad (Eng) shows the noise band as in the sim.
- [x] Tape Image with a loader then a short program (tester: "FILO, not the queue's FIFO"): BASIC 1Z-013B loaded, but LOAD never got the 1.3 KB BASIC program after it. The tape image loads the next record as soon as the CMT drops PLAY_READY, inside the 64K-clock PLAY_READY_CLR pulse, which overrode every buffer write, so a short record never became ready (a long one outlasted the pulse). `cmt.vhd` now clears on the pulse's rising edge only. Sim test `tape_basic`, hardware test L12.
- [x] Full hardware run 2026-10-08 (releases/SharpMZ_20261008.rbf, 115 tests, out/mister_full*): no regressions. Everything matches the earlier runs or the expected prompts (Quick Disk products dumped to tape ask for their disk, BASIC tapes give "File mode error" at the MZ-2000 IPL, DISK37 with CRC Report says "Loading error", the Flicky tape is only its loader). T02, T25 and T26 caught the screen too soon after a model change; they pass on their own.
- [x] Faster hardware runs: a wait before a screenshot ends when the screen matches that screenshot from a good run (`tools/mister_refs.json`, md5 of Main's PNG, several variants for a blinking cursor; `--update-refs` adds them); one ssh connection (ControlMaster); files the MiSTer already has are not copied again; `--quick` (24 tests, about 9 minutes); MZ-2000 tape tests at Fast Tape 32x. Deploying all 115 tests to the menu takes under a minute.
- [x] Tester build `releases/SharpMZ_20261009b.rbf`: OSD Reset fixed.
- [x] Tester build `releases/SharpMZ_20261011.rbf`: OSD Keyboard Layout (PC default), MZ-1200 keys.
- [x] First release `releases/SharpMZ_20261012.rbf` (2026-10-12): OSD cleaned up (Fast Tape Fastest by default, CPU Speed Normal..Fastest, Tape Sound Off/Mix/Only, Load Direct Start, no Load Keymap / Video / Graphics), project files SharpMZ.*. Full hardware suite, 133 tests, all pass (52 on the 10.0.2.192 MiSTer, 81 on mister126).
- [ ] Later: v2 machine options (RAM size, GRAM, MZ-1R25), and removing `support/sharpmz/` from Main_MiSTer.
- [x] MZ-2500/2520: researched in `docs/mz2500.md`; now its own project, https://github.com/alanswx/SharpMZ2500_MiSTer (`~/dev2/SharpMZ2500_MiSTer`: skeleton core, Verilator sim, docs, phased TODO).

## Known issues
- Changing the model doesn't reset MZ-800 characters redefined through C000; the IPL restores the font on the next boot.
- The author's framebuffer graphics extension (bitmap graphics for the MZ-700/80A) isn't included.

## Hardware test log
- **2026-09-29, MZ-700:** Galactic Invaders loads from tape and plays (SHIFT fires, SPACE pauses as the game intends). This found the keymap bugs fixed in `cbb1c04`.
- **2026-09-30, all models (`tools/mister_test.py`):** T01-T06 boot screens correct on every model (MZ-2000 on the MZ-2200 IPL). T07 MZ-700 tape, T08 MZ-700 floppy, T09/T10 MZ-800 graphics tests pass. T11/T12 MZ-800 games load from tape images (Cauldron II, Cybernoid) after the tape image fix. The user played MZ-800 CP/M games from disk (sound fixed in `11f2d8b`). T13-T18 on b4004ff: MZ-800 CP/M 4.1 (DIR), CP/M 1.3 and the Hry file manager boot from floppy; MZ-80B boots SB-6511 Disk BASIC and CP/M 2.2; the MZ-2000 loads MZ-80B CP/M and stays blank, as in the sim. T19/T20 play the BELL and 440 Hz tone (by ear).
- **2026-10-02, tapes and keys (build 2ca6911):** all twelve MZ-1500 tape tests now get their `C` (80 ms key hold): Pac-Man, Mario Bros. Special, Thunder Force, Star Fighter and Xetter '91 reach their titles; Mappy, Dig Dug, Rally-X, Door Door, Flappy and Druaga ask for their Quick Disk; Galaga stops at "QD: Not ready". Xetter '91's text was mirrored (CG read bit order, fixed). T03 (MZ-700), T25/T26 and W01 unchanged.
- **2026-10-02, Quick Disk writes (build fdb8de9):** W01: MZ-5Z001 BASIC boots from a disk made by `mzf2qdf.py`, `INIT "QD:"` formats it, `SAVE "TEST"`, `NEW`, `LOAD "TEST"`, `RUN` prints the result; the fetched image has the count, format mark, header and body blocks with good CRCs. BASIC had hung before READY: the Z80 PIO dropped a /CTC0 condition that changed while its interrupt was disabled (fixed as in mz800emu). G01-G08: Druaga, Rally-X, Dig Dug, Mappy, Door Door MkII, Knither, Zolvass and Burnin' Rubber reach their title screens from tape images turned into Quick Disks. W02 showed the Druaga tape is not an installer: it asks for QD side B.
- **2026-10-02, MZ-1500 software (build aa0e0a7):** Quick Disk: Nintendo Tennis runs; Battle City, Grobda, Milky Way and Batten Tanuki load side A, ask for side B and reach their title/demo once the MGL swaps it in. Tapes: Rally-X, Thunder Force, Door Door MkII and Druaga load their DATA files (Quick Disk products: side A asks for side B, see the entry above); Pac-Man, Mappy, Dig Dug, Mario Bros. Special, Flappy, Star Fighter, Xetter91 and Galaga missed the `C` keypress in the test run.
- **2026-10-01, MZ-1500 (build 5eda577):** T25 IPL menu, T26 Lode Runner from Quick Disk with the PCG title screen; MZ-700 unchanged (T03).
- **2026-10-01, MZ-80B/2000 (clean build 9b9001e):** T21 MZ-80B SB-5520 BASIC from tape, T22 Gang Man, T23 TF-DOS D88 with katakana, T24 Zero Fighter in colour. All match the sim.

## Bugs found and fixed
Each has a commit; this list is for context.
- **MZ-80B/2000 NST:** PC1 going high must reset the CPU (the IPL's jump into RAM); the core carried on at 0008 inside the loaded program (Zero Fighter crashed).
- **Stale FPGA ROM contents:** a Quartus incremental build kept the old character ROM after only the MIF changed; builds are now clean (`rm -rf db incremental_db`).
- **MZ-80B/2000 tape never played:** GHDL lost the CMT state process's writes to CMT_BUS_OUTi (the vector was split between the process and concurrent assignments), so the APSS deck never left reset; and the deck needed PLAY high with STOP low, which the MZ-2200 IPL never does. Now registered bits and edge-triggered commands, as MAME.
- **Tape image lost on reset:** a machine reset cleared the CMT but the tape engine still thought its record was loaded, so a tape mounted before Reset (or an MGL `<reset>`) never played. It now reloads after a reset.
- **Tape image hang (hardware):** mounting a tape image froze Main (F12 dead, reboot needed). `ioctl_wait` was tied to the tape engine and holds the whole HPS link, so Main could not serve the engine's sector reads. The engine now yields to downloads instead.
- **OSD/MGL:** MGL files can only load F/S entries on the first OSD page; ours were on sub-pages, so every MGL with a tape or disk was dropped.
- **MZ-700/800 sound:** the beeper played an octave low (a divide-by-2 meant for the MZ-80K's 2 MHz clock), and on the MZ-800 counter 0's gate was forced on in 800 mode, so games that switch modes (Astro Marine Corps) clicked.
- **MZ-700 tape record decoder:** never decoded (sample point 1302 T; the monitor reads at ~990 T), so SAVE never produced a file.
- **MZ-700 sound pitch:** ~10% low (8253 clock 1 MHz instead of 1.1088 MHz).
- **ROM banks:** the User ROM (E800) and FDC ROM (F000) banks were never selected (the monitor clauses caught those addresses first), and the MZ-2000's banks were decoded as a second MZ-80B set.
- **mctrl:** MZ-80B RTC speed never selected; MZ-2000 ran at 2 MHz; the reset one-shot only ended by wrapping.
- **GHDL 5.1** drops port-alias assignments in Verilog output (`verilator/fix_port_aliases.py`).
- **v2 VideoController:**
  - wrong 50 Hz timing rows;
  - leftmost pixel lost;
  - MZ-800 frame gating in the write modes;
  - 640x200 plane III;
  - 16-colour palette index;
  - frame-A colour search;
  - half-word RAM read (also in the author's v2).
- **Keyboard:** extended keys never reached their keymap entries; MZ-700 map errors (4 typed C, missing keys).
- **Floppy:** `wd1793.sv` Force Interrupt status.
- **i8255:** a mode set didn't clear the outputs, so CP/M 1.x on the MZ-800 took endless 8253 interrupts.
- **wd1793.sv:** an EDSK image with an unformatted track before the first formatted one was never parsed.
- **VideoController:** 640x200 hardware scroll overflowed 14 bits with large offsets, so CP/M 4.1 drew text over itself after scrolling a while.
