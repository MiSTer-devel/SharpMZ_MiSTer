# SharpMZ Verilator simulation

Runs the core headless on the host. It can boot any model, type at it, load and save tapes, boot floppy disks, and write screenshots, frame logs, audio, CPU/I/O traces and memory dumps. No DE10-Nano or Quartus is involved.

The options match the headless CLI of the reference emulator in `../refs/mz800emu` (`HEADLESS_CLI.md` there), so the same scenario can be run on both and compared.

## Build and run

```sh
cd verilator
make                 # -> ./obj_dir_headless/Vtop
make fast            # -> ./obj_dir_fast/Vtop: the same core at half clk_sys, about 2x faster (see Speed)
make test            # regression tests (run_tests.sh; QUICK=1 skips the slow tape tests)
make test-clkgen     # GHDL testbench: clock enable rates and jitter
make test-i8254      # GHDL testbench: 8253 power-up, modes 0/2/3, counter latch (seconds)
make test-cmt        # GHDL testbench: tape playback byte for byte, record kept over a deck stop (~15 min)
./obj_dir_headless/Vtop --help
```

Needs GHDL 5.x, Verilator 5.x and Python 3 (`brew install ghdl verilator`). **Run the binary from this directory**, because the RAM init files are loaded from `./software/mif/*.hex`. Run from anywhere else, the ROMs are silently left empty and the screen stays blank.

## How the build works

1. `ghdl synth` turns `../rtl` (VHDL) into a Verilog netlist, `gen/sharpmz.v`. Module, instance and register names survive.
2. Two fix-ups are applied to the netlist:
   - VHDL names that are Verilog keywords (`do`, `config`) are renamed.
   - `fix_port_aliases.py` restores `SIG <= in_port;` assignments that GHDL 5.1's Verilog writer drops.
3. `dpram`/`dprom` (Altera `altsyncram` wrappers) are black boxes, implemented by `rtl_v/dpram.v` and `rtl_v/dprom.v`. `mif2hex.py` converts the `.mif` init files for `$readmemh`, so the ROMs are built in, as on hardware.
4. `sim.v` instantiates `rtl/sharpmz_top.sv`, the module `SharpMZ.sv` uses between hps_io and video_mixer. The configuration from the OSD status bits, the download routing, the resets, the tape image, Load Direct, the floppy, the Quick Disk, the printer, the border and the tape messages are therefore the hardware's own. `sim.v` adds:
   - a behavioural DDR3 for the tape buffer, with random BUSY and read latency;
   - hps_io's image slots, which hold the last mounted image's size and read-only flag;
   - debug taps into the core.
5. `sim_headless.cpp` emulates Main's side of hps_io:
   - the 128-bit OSD status word;
   - key presses;
   - downloads, sent with their file index (F1 tape, F2 direct, F3 ROM) and file offsets, as Main sends them;
   - the 512-byte sector handshake of the image slots (S0 tape, S1/S2 floppy, S3 Quick Disk).

## Options (main ones)

| Option | |
|---|---|
| `--model M` | mz80k, mz80c, mz1200, mz80a, mz700, mz800, mz80b, mz2000 or mz1500 |
| `--osd "NAME=VALUE, ..."` | Set OSD options by the names and values in `SharpMZ.sv`'s CONF_STR, case-insensitive, e.g. `--osd "Fast Tape=Off, MZ-800 Border=On"`. A value's index also works. Repeatable, and applied after the other options. `--osd-list` prints every option with its status bits and values. The sim's own defaults differ from the core's in a few places (Keyboard Layout Sharp, Fast Tape Off, Load Direct Start Reset Only, Tape Messages Off, MZ-800 Mode MZ-800) so the regression's expected results hold; `--osd` sets the core's. |
| `--stop-at-frame N` | Run to frame N. |
| `--screenshot N`, `--dump-every N` | PNGs of frames. |
| `--ascii-end` | Print the text screen at exit. |
| `--frame-log FILE` | Per frame: hash, CPU cycles, PC. |
| `--type FRAME:TEXT` | Type text from a frame on, with escapes like `\n` and `{WAIT n}`, and key names such as `{LEFT}`, `{BS}`, `{BREAK}`. |
| `--mzf FILE` | Put an MZF on the tape through the core's CMT download (file index 1; no longer in the OSD, which uses the tape image, but kept for the tests). `--mzf-direct` / `--mzf-direct-frame N` load it into RAM instead (index 2, OSD Load Direct to RAM). |
| `--direct-start` | After a direct load, start the program as the core's Load Direct: Start Program does (boot, restore 10F0-11FF, jump to exec). Off by default in the sim, so the tests that type `J` still work. |
| `--tape-image FILE` | Mount a tape image (S0). Also `--tape-readonly`, `--tape-rewind`. |
| `--fast-tape STEP` | The OSD Fast Tape step (0–7), not a multiplier. 4 is about 8x; 5 is the fastest (capped at clk_sys/2). |
| `--fdd FILE` | Extended DSK image in floppy drive A. Also `--fdd-readonly`, and `--fdc-mode auto\|on\|off`. |
| `--fdd-b FILE` | Image in floppy drive B (shares `--fdd-readonly`). `--fdd-b-hd` makes drive B answer as unit 2 (OSD Floppy > Drive B Unit: 3rd), CP/M 4.1's 1440K drive C:. |
| `--ramdisk` | MZ-800 64 KB RAM disk board (OSD MZ-800 RAM Disk). |
| `--qd FILE` | Quick Disk image (`.qdf` or `.mzq`) in slot S3 (MZ-1500, MZ-800); writes go back to the file. `--qd-readonly` mounts it write protected. |
| `--qd-swap FRAME:FILE` | Mount another Quick Disk image at FRAME, e.g. side B of a two-sided game (repeatable). |
| `--printer FILE` | Printer connected (OSD Printer: UART); the UART line is decoded into FILE. `--printer-baud N` (9600). Feed FILE to `mister_printerd -d - -m sharpmz` (plotter) or `-m epson` for a PDF. |
| `--joy0 N` | Hold joystick 1 with MiSTer bits N (decimal; 0 right, 1 left, 2 down, 3 up, 4 fire 1, 5 fire 2) all run. |
| `--warm-reset N` | Press the OSD Reset at frame N (repeatable). |
| `--load-rom F:FILE[@ADDR]` | OSD Load System ROM at frame F: FILE written to the system ROM from hex offset ADDR (default 0, the MZ-80K 40-column monitor). No reset; add `--warm-reset`. |
| `--fast-tape-at F:STEP` | Change the Fast Tape step at frame F, e.g. load a BASIC fast and then a program at real speed. |
| `--mz800-mode 700\|800` | The MZ-800 rear switch (default 700, as mz800emu). |
| `--turbo N`, `--vmode` | CPU speed step; video mode. |
| `--trace-cpu FILE` | PC of every opcode fetch; `--trace-from`/`--trace-to` limit the frames. |
| `--trace-io FILE` | Every I/O write: frame, PC, port, data. Also the E-page video registers as `frame,pc,mem,R/W,address[,data]`: writes to E010-E012 (PCG-700) and reads of E014/E015 (invert) and E200-E2FF (MZ-80A scroll). |
| `--wav FILE` | Audio at 48 kHz, as `SharpMZ.sv` mixes it. |
| `--dump-mem A:L:FILE` | Main RAM at exit (hex address and length). |
| `--verbose` | Tape status and deck lines (`[cmt]`), record FSM and pulse widths, the tape transmitter's block type and state (`[xmit]`), MZ-800 mode changes, sound. |

## Tests

`run_tests.sh` runs everything in parallel and writes `out/test/<name>.*`:

| Test | Checks |
|---|---|
| `boot_<model>` | Boot to frame 150 and compare the text screen (MZ-80K/80C/1200/80A/700/800). |
| `kb_mz700` | Typing letters, digits, symbols, cursor keys and DEL at the MZ-700 monitor (matches mz800emu). |
| `mon_mz800` | `M` at the MZ-800 IPL starts the 9Z-504M monitor. |
| `gfx_mz800`, `pcg_mz800`, `m800_*` | MZ-800 graphics modes, write/read modes, scroll and CG-RAM, by frame hash. The pictures match mz800emu; `tests/mz800/compare_emu.sh` redoes the comparison. |
| `psg_mz800` | The PSG plays 439.8 Hz (measured from `--wav`). |
| `beep_mz700`, `beep_mz800` | The monitor BELL, then 8253 counter 0 at 440 Hz (measured from `--wav`); the MZ-800 runs it in 700 mode with PC0 set. |
| `fdd_mz700` | The MZ-700 boots a disk made by `tools/make_boot_disk.py` with `J F000` (MZ-1E05 ROM). |
| `fdd_mz80b`, `fdd_mz80b_cpm` | The MZ-80B IPL boots SB-6511 Disk BASIC and CP/M 2.2 (images from idealine.info in `../software/idealine/`). |
| `ipl_mz2000`, `tape_mz80b`, `tape_mz2000` | The MZ-2000 IPL; MZ-80B BASIC (SB-5520) and Gang Man from tape images (`../software/mz80b`, `mz2200`). |
| `fdd_hd` | MZ-800: a 1.44 MB image on unit 2 (`--fdd-b-hd`); `tests/fdd/fdhd.mzf` writes and reads back a sector 1.45 MB into it (status bytes, byte count, data). Needs `../software/dsk/_Vzor144.dsk`. |
| `ipl_mz1500`, `qd_mz1500` | The MZ-1500 IPL menu; Lode Runner from a Quick Disk dump with its PCG title screen (pixel-identical to mz1500emu). |
| `cg_mz1500` | MZ-1500: `tests/mz1500/cgread.mzf` reads 'F' from the CG ROM through OUT E5 0 and prints it in hex (bit 7 = left pixel). |
| `joy_mz800` | MZ-800 with `--joy0 17` (right + fire 1): `tests/mz800/joytest.mzf` strobes the 8255 (PA4 low = joystick 1) and reads F0/F1. |
| `prn_mz700`, `prn_mz800` | `tests/printer/prntest.mzf` prints two lines through the printer port (MZ-700 FE/FF, MZ-800 PIO); the bytes decoded from the UART match. |
| `rd_mz800` | MZ-800 with `--ramdisk`: `tests/mz800/ramdisk.mzf` writes two bytes to the RAM disk board and reads them back. |
| `tape_image`, `tape_mz800` | Load from a tape image, on the MZ-700 monitor and the MZ-800 IPL. Slow; skipped with `QUICK=1`. |
| `fdd_cpm`, `fdd_hry` | CP/M 4.1 boots from disk and runs DIR; a games disk starts its file manager (pixel-identical to mz800emu). They need the images in `../software/dsk/` (not in the repository) and are skipped otherwise. |

The test programs are in `tests/mz800/`, with the Python scripts that generate them.

## OSD option sweep

`python3 ../tools/osd_sweep.py` runs the sim once for every value of every OSD option, each on a model the option affects, from the core's defaults. It reports which runs fail and which change the picture against that model's default run, in `out/osd_sweep/report.md`, with a screenshot per run. `--only NAME` limits it to some options, and `--frames N` sets the run length. Scandoubler Fx and Aspect ratio act in video_mixer, outside the sim, so they are listed as hardware-only. `tools/sharpmz_osd.py` is the CONF_STR reader the sweep and `tools/mister_test.py` share, so hardware tests name options the same way (`osd('Tape Image Start=Direct')`).

## Notes

- **Frames:** a frame is counted at each vsync after the machine is configured; frame 0 is the first.
- **`fb_hash`:** FNV-1a 32 over the RGB888 bytes of the active picture (e.g. 320x200), the same bytes as the PNG. mz800emu includes its border unless run with `--crop canvas`; `tests/mz800/cmp_emu.py` compares a screenshot with an mz800emu canvas.
- **Comparing traces with mz800emu:** our `--trace-cpu` logs every opcode fetch (prefixed instructions appear twice), while mz800emu logs each instruction.
- **`--dump-mem A:L:FILE`:** reads physical main RAM, not the CPU's banked view. A and L are hex (`1200:100:ram.bin`).
- **Tape speed:** real-speed tapes have a 10 s lead-in, so use `--fast-tape 4` or `5` to save time.
- **Speed:** about 1/60 real time (~1.2M clk_sys cycles per second on an M-series Mac, 1.2 s a frame). A 450-frame run takes about 9 minutes. The time is spread over the whole model (a profile shows no hot spot, and clang PGO gained only 7%), so for batches run many sims at once, one per core.
- **`make fast`:** builds the same RTL with clk_sys at 35.47 MHz instead of 70.94 MHz (a copy of `clkgen_pkg.vhd` with `CLK_SYS_HZ / 2`; every clock enable, the key hold and the Quick Disk byte time follow it), into `obj_dir_fast`. Half the cycles per frame, so about twice as fast. MZ-700/800 rates stay exact. Not for: the 640-pixel modes and turbo above 17.7 MHz (the video controller and the CPU are capped at clk_sys/2), and exact floppy timing (the controller fills its sector buffer at clk_sys rate, so disk boots finish a little later: `fdd_mz700`, `fdd_cpm`, `fdd_hry` differ), and the MZ-80B/2000 (`tape_mz80b`, `tape_mz2000` differ). Use it for MZ-700/800/1500 batches; 36 of the 41 tests match the full-rate build. `BIN=./obj_dir_fast/Vtop OUT=out/test_fast ./run_tests.sh` shows which tests differ. `../tools/triage.py` uses it.
