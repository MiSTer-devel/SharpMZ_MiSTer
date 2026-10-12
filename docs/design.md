# SharpMZ standard core: design notes

How the core is put together, and the hardware facts it relies on. `TODO.md` has status and open work; `verilator/README.md` has the simulation and tests.

**References:**
- `refs/` (gitignored, see `refs/README.md`): mz800emu (the behavioural reference for the MZ-700/800), the author's v2 design (tranZPUter, `FPGA/SW700/v1.3/MZ700/`), and sharpmz.net documents.
- mz800emu has a headless CLI with the same options as our simulator (`refs/mz800emu/HEADLESS_CLI.md`), so the same scenario can be run on both and compared.

## Structure

```
SharpMZ.sv           MiSTer top: hps_io, OSD, PLL, tape image, floppy, video/audio out
  rtl/tape_image.sv    tape image slot (S0) <-> the CMT buffers
  rtl/tape_ddr.sv      CMT tape buffer in DDR3 (port A the CMT, port B the host download / tape image)
  rtl/direct_start.sv  Load Direct: restore 10F0-11FF after the boot and start the program
  rtl/mz_printer.sv    printer port -> 512-byte FIFO -> MiSTer UART (8N1)
  rtl/mz_fdc.sv        floppy interface, 2 x rtl/wd1793.sv (S1/S2)
  rtl/sharpmz.vhd      the machine: T80, RAM/ROM, clkgen, mctrl, cmt, keymatrix, video
    rtl/mz80c/mz80c.vhd    MZ-80K/80C/1200/80A/700/800 hardware (8255, 8253, MZ-800 branch)
      rtl/mz80c/mz800_pio.vhd  MZ-800 Z80 PIO
      rtl/sn76489_audio.vhd    MZ-800 PSG
    rtl/mz80b/mz80b.vhd    MZ-80B/2000 hardware
    rtl/vc/                v2 VideoController and its wrapper (video_vc.vhd)
```

`rtl/sharpmz.vhd` has an external I/O port (`EXT_IO_*`, `EXT_INT_n`, `EXT_CE_CPU`) for the Verilog floppy interface. GHDL can't read SystemVerilog, so the floppy lives outside the VHDL.

## Clocks

- **clk_sys** is 70.9376 MHz, 4× the MZ-700's 17.7344 MHz crystal, from a Template PLL.
- `rtl/clkgen.vhd` makes every other rate as an accumulator clock enable:
  - CPU: 2, 3.547 or 4 MHz, plus turbo steps capped at clk_sys/2.
  - 2 MHz peripheral.
  - 8253 sound and RTC inputs, as square waves.
  - A fixed 3.547 MHz PSG enable.
- **Exact and jittered rates:** the MZ-700/800 rates are exact divides. The 2/4/8/16 MHz family jitters by one clk_sys.
- **No signal-as-clock logic:** everything is edge-detected on clk_sys.

## Video

The author's v2 VideoController (`rtl/vc/VideoController.vhd`), changed as follows:
- **Clocking:** its PLLs and clock switch are replaced by a `VID_CE` enable at 2× the dot clock; `CE_PIXEL` goes to the framework.
- **Timing:** native only, 50 Hz for the MZ-700/800 and 60 Hz for the others. The host registers A0–BF and the OSD/GPU paths are disabled, and Quartus removes the logic.
- **RAMs:** `rtl/vc/vc_rams.vhd` rebuilds them on `rtl/dpram` byte lanes. An address ending in `10` returns the upper half-word, which MZ-800 640×200 read-modify-write needs.
- **CG ROM:** v1's 32 KB `combined_cgrom.mif`, banked per model. The MZ-800 bank holds the MZ-800 font (the MZ-700 font bit-reversed); the CPU writes it through C000 as CG-RAM in 700 mode.
- **Palette:** a fixed LUT. MZ-800 colours use mz800emu's measured palette; 700 mode uses its bright half.
- **Wrapper** (`video_vc.vhd`): translates CONFIG to the v2 layout, gates MREQ with the machine's decode, and keeps v1's VRAM wait states.

## Tape

- `rtl/cmt.vhd` plays and records MZF records.
- PLAY_READY goes up half a second after the last write to the CMT buffer and down when the machine has finished a
  record (PLAY_READY_CLR, taken on its rising edge: the tape image refills the buffer right away and those writes
  must restart the timer).
- A record plays as gap, tape mark, block (header or data), 256 short pulses, the block again (backup copy).
  If the machine leaves the motor on past the end of a record (a search for a named program), the record is
  released as on a motor stop and the next one, once the tape image has loaded it, follows from its gap. The MZ
  stops the deck once it has the first copy; on a stop the padding and block transmitters both give up their
  sequence, so the next PLAY starts clean (the block transmitter used to run on to the end of its copy).
- `rtl/tape_image.sv` feeds it from an MZT/MZF image on slot S0. It loads the next record when the machine stops the tape, and appends records the machine saves (the image must have spare room, e.g. from `tools/make_blank_tape.py`).
- The MZ-700 and MZ-800 use the same pulse timings: short/long 676/1300 T-states, sampled 988 T-states after the edge.
- The tape data buffer is in DDR3 (`rtl/tape_ddr.sv`, byte address 0x30000000), freeing block RAM for the 1.44 MB
  floppy tables. The CMT waits on `TAPEDATA_READY`; each port keeps one cached line, written through.

**Load Direct** (`rtl/direct_start.sv`). The download writes the MZF header to 10F0 and the body to its load address
during a warm reset. With Load Direct: Start Program (default) and an MZF type 01, the module keeps what was written
to 10F0-11FF, lets the machine boot for 1.5 s (the IPL/monitor set up the 8255, 8253, PIO and video, and use 10F0-11FF
as their work area), writes the kept bytes back over the download bus, then puts a short program on the CPU's data bus
for its next memory reads, starting at an opcode fetch: `NOP, DI`, the bank switches (MZ-800: `IN A,(E1)` to take
the CG ROM and VRAM out and `OUT (E3),A` for the ROM at E000, the map mz800emu's start leaves; with E0-E4:
`OUT (E0),A` when it loads below 1000), `LD SP,10F0`, `JP exec`, from the first opcode fetch after the next start of
vblank (a fixed phase against the display interrupts, as mz800emu starts at a frame boundary). This follows mz800emu's `mzarch_bootstrap_run_mzf`. The MZ-80B/2000
only reset.

## MZ-800

The MZ-800 is a branch of `mz80c.vhd` selected by `CONFIG(MZ800)` (the `M8_*` signals), following mz800emu. The v2 `mz80k_hw.vhd` is a reference only.

**Memory map.** One 5-bit register (ROM_0000, ROM_1000, CGRAM_VRAM, ROM_E000, PROHIBITED). The display mode register DMD (port CE) chooses the layout: bit 3 = 700 mode, bit 2 = 640 wide. Reset gives ROM_0000|ROM_1000|ROM_E000 and DMD=08.

| Area | Mapped when | Otherwise |
|---|---|---|
| 0000-0FFF | ROM_0000: ROM | RAM |
| 1000-1FFF | ROM_1000: CG ROM | RAM |
| 8000-9FFF | 800 mode and CGRAM_VRAM: VRAM | RAM |
| A000-BFFF | as 8000, and 640 wide | RAM |
| C000-CFFF | 700 mode and CGRAM_VRAM: CG-RAM | RAM |
| D000-DFFF | 700 mode and ROM_E000: VRAM | RAM |
| E000-FFFF | ROM_E000: ROM, except E000-E00F (below) | RAM |

**E000-E00F with ROM_E000 set:**
- 700 mode: E000-E008 are the memory-mapped 8255/8253/E008 ports, and E009-E00F read 1A.
- 800 mode: E000-E00F read FF.
- PROHIBITED makes all of E000-FFFF read 1A; only OUT E6 clears it.

**Bank ports:**
- OUT E0 clears ROM_0000 and ROM_1000.
- OUT E1 clears ROM_E000.
- OUT E2 sets ROM_0000.
- OUT E3 sets ROM_E000.
- OUT E4 sets all four; in 700 mode it then clears ROM_1000 and CGRAM_VRAM.
- OUT E5 and E6 set and clear PROHIBITED.
- IN E0 sets ROM_1000 and CGRAM_VRAM; IN E1 clears them.

**ROM.** One 16 KB chip from mz800emu (`rtl/software/roms/MZ800_*.rom`), placed at 0x1C000 of the combined monitor ROM by `tools/add_mz800_rom.py`. It holds the 1Z-013B at 0000, the CG at 1000, and the IPL/9Z-504M at E000.

**I/O:**
- D0-D3 is the 8255 and D4-D7 the 8253, in 800 mode only.
- CC-CF, F0: the display controller (WF, RF, DMD, CRTC, palette).
- IN CE status: 7 /HBLNK, 6 /VBLNK, 5 /HSYNC, 4 /VSYNC, 1 the rear mode switch, 0 TEMPO.
- F2: the PSG.
- FC-FF: the Z80 PIO.
- D8-DF: the floppy.

**Rear mode switch** (OSD "MZ-800 Mode"). IN CE bit 1 = 1 is the MZ-800 position: the IPL switches to MZ-800 graphics before starting a program loaded from tape. The default is MZ-700, as in mz800emu.

**Clocks and wiring:**
- CPU 3.547 MHz. 8253 CLK0 1.108 MHz, CLK1 = HSYNC, and OUT1 clocks counter 2.
- Sound = OUT0 AND PC0; counter 0's gate is 1 in 800 mode.
- INT = (OUT2 AND PC2) OR the PIO. PC2 masks the 8253 interrupt, so the 8255 must clear it on a mode set.

**Display controller.** It's in the VideoController:
- 320×200 in 4 or 16 colours, frames A/B;
- 640×200 in 2 or 4 colours;
- all six write modes, single and search reads, hardware scroll.

The MZ-1R25 VRAM expansion is enabled, as in mz800emu. The write rules follow mz800emu's `vramctrl`: SINGLE/EXOR/OR/RESET write the selected planes the resolution has, and only REPLACE and PSET use the frame bit.

**Z80 PIO** (`mz800_pio.vhd`). Bit-mode interrupts with the IM 2 vector on the acknowledge. PA4 = /CTC0, PA5 = /VBLN. CP/M runs its keyboard and clock from the vertical blank interrupt. An acknowledged port stays in service until the CPU fetches RETI (ED 4D; the PIO sees the CPU's input bus): meanwhile it and the lower priority port B don't request, and a condition that becomes true stays pending, as on the Z80 PIO and in mz800emu.

**PSG.** `sn76489_audio.vhd` (Matthew Hagerty) on the fixed 3.547 MHz enable, mixed with the 8253 into 16-bit audio.

## Floppy (MZ-700/MZ-800)

`rtl/mz_fdc.sv`, ports D8-DF, from mz800emu `fdc.c` and the MZ-1E05 service manual:

| Port | Function |
|---|---|
| D8-DB | MB8876A (WD1791 class): status/command, track, sector, data. The data bus is inverted both ways; DSK images hold the chip-side bytes. |
| DC | Bit 7 motor; bit 2 set loads the drive number from bits 1:0. |
| DD | Bit 0 = side (the DSK side, as written). |
| DE | Density (ignored). |
| DF | Bit 0 EINT, the MZ-800 "HD patch": /INT = EINT AND DRQ. CP/M 4.1 transfers every byte in the interrupt routine. |

**Drives.** Each drive is Sorgelig's `wd1793.sv` from FM-7_MiSTer, which reads Extended CPC DSK images through the image slot and parses the track and sector tables at mount. One change was made: a Force Interrupt during a Type II command keeps the Type II status, because the IPL checks for 00.

**Bus behaviour:**
- Commands and reads go to the selected drive; track, sector and data writes go to both (one register set on the real controller).
- The interrupt is held off from the data access until DRQ falls, so a turbo CPU doesn't take a byte twice.

**OSD.** "Floppy Interface" Auto (default) presents the controller only while a disk is mounted, so the IPL doesn't wait at "Make ready FD". On or Off force it.

**Boot.** With the controller present, the 9Z-504M IPL boots from floppy by itself:
1. It reads the boot record (`IPLPRO`) from track 0 side 1 (16 × 256-byte sectors).
2. It loads the loader at 0000.
3. CP/M 4.1 then uses the 9 × 512-byte format on both sides.

## Keyboard

- `rtl/keymatrix.vhd` looks up each PS/2 code, with bit 7 = extended, in a per-model table (`combined_keymap.mif`) giving the MZ matrix row and column.
- `tools/fix_keymap.py` patches the tables after romtool:
  - the MZ-700/800 table follows mz800emu's layout;
  - extended keys without an entry get their keypad twin's.

## Known quirks kept from v1
- The MZ-80B Z80 PIO interrupt: `z8420.vhd` connects the active-low reset to the interrupt logic's active-high reset. Behaviour is unchanged until MZ-80B software needs it.
- The first MROM_BANK clause for each model in `sharpmz.vhd` has no address condition, so the User ROM (E800) and FDC ROM (F000) banks are never selected.
