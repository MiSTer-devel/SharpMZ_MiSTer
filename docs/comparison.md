# How this core compares

Other Sharp MZ implementations, as of 2026-10-02. "v2" is the original author's tranZPUter SW-700 emuMZ RTL (`refs/tranZPUter`, the
base of this port); NibblesLab's are the Terasic DE0 cores (github.com/NibblesLab); mz800emu is Michal Hucik's emulator, our reference
for the MZ-700/800/1500; MAME is 0.264 with its own driver status flags. Sources: our own surveys of each (TODO.md history).

## Machines

| Model | This core (MiSTer) | v2 (tranZPUter) | NibblesLab DE0 | mz800emu | MAME 0.264 |
|---|---|---|---|---|---|
| MZ-80K / 80C / 1200 / 80A | Yes | Yes | Yes (`mz80c_de0`) | No | Good (80K, 80A) |
| MZ-700 | Yes | Yes | No | Yes | Good |
| MZ-800 | Yes, all graphics modes, frame-matched to mz800emu | Yes | No | Yes (reference) | Preliminary |
| MZ-1500 | Yes: PCG, 2 PSGs, Quick Disk | Partial: 2nd PSG and palette, no PCG, no QD | No (`vup1500` is a PSG/PCG add-on board) | Yes | Preliminary |
| MZ-80B | Yes: tape and floppy | Yes | Yes (`mz80b_de0`) | No | Preliminary |
| MZ-2000 / 2200 | Yes: real IPL, colour graphics, katakana | Yes | Yes (`mz80b_de0`) | No | Preliminary |
| MZ-2500 | No (feasibility study: `docs/mz2500.md`) | No (model constant only) | No | No | Imperfect |

## Features

| Feature | This core | v2 | NibblesLab DE0 | mz800emu | MAME |
|---|---|---|---|---|---|
| Tape | MZF/MZT images, multi-program, SAVE into an image, MZ-80B/2000 APSS, fast tape up to 32x | Host loads MZF from SD; record marked unfinished | Real-speed MZT through a Nios II; no write | Yes, plus WAV | WAV/MZF |
| Floppy | MB8876 on MZ-700/800/80B/2000; Extended DSK and D88/D77; 2 drives | All models; the host converts images; 4 drives | MZ-80B/2000 (`mz80b_de0`) | Yes | Per driver |
| Quick Disk | Yes (MZ-1500, MZ-800), `.qdf` dumps and `.mzq`; read and write (BASIC format/save on hardware) | No | No | Yes, read/write | Preliminary drivers |
| MZ-800 graphics | 320/640 x 200, 4/16 colours, frames A/B, write modes, scroll | Yes, with bugs we fixed | — | Yes | Preliminary |
| MZ-1500 PCG | 3 planes, palette, priority; pixel-identical to mz1500emu | No | — | Yes | Preliminary |
| Sound | 8253 beeper; SN76489 (MZ-800), two in stereo (MZ-1500) | Beeper, 1-2 PSGs, mixer | Beeper | Yes | Yes |
| Joystick / printer | Not yet | Stubs | No | Yes | Varies |
| CPU turbo | Up to about 35 MHz | Up to 56-64 MHz | 4 MHz | — | — |
| Display | Native timing through the MiSTer scaler (HDMI/VGA) | Own scan converters and OSD planes | VGA line doubler | Window | Window |
| Verification | 36 sim tests (many frame-matched to mz800emu) and 57 MGL tests on hardware | — | — | Reference | — |

## Where this core is ahead

- The only FPGA core with the MZ-1500 (PCG and Quick Disk), and the only FPGA core with Quick Disk.
- MZ-800 graphics checked frame by frame against mz800emu; 8 bugs fixed in the VideoController code taken from v2.
- MZ-80B/2000 tape and floppy work through their IPLs (v2's MZ-80B video was marked untested; MAME's drivers are preliminary).
- A standard MiSTer core: MGL files can load tapes and disks, and the sim and hardware suites run unattended.

## Where others are ahead

- v2: higher turbo, four floppy drives, floppy on every model including the MZ-80K/80A.
- mz800emu: joysticks, printer, RAM disk boards, the virtual (directory) Quick Disk.
- MAME: the MZ-2500 (imperfect), and WAV tape input.
