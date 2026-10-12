# MZ-800 tests

`gfx320.mzf` (load and exec 2000h) sets the MZ-800 320x200 4-colour mode, palette 0-3 = black, light red, light green, white, and fills plane I in the top 100 lines with FF and plane II in all 200 lines with 0F. Expected picture: top half 4 white / 4 light red pixels, bottom half 4 light green / 4 black (bit 0 is the leftmost pixel).

It matches mz800emu:

    mz800emu --headless --model mz800 --type 160:M --mzf gfx320.mzf --mzf-direct --mzf-direct-frame 200 \
             --stop-at-frame 321 --screenshot 320

(mz800emu's lower lines also show whatever was in plane I before; the simulation starts with clear VRAM.)

`make_gfx320.py` writes the MZF.

## Graphics modes

`make_gfx_modes.py` writes programs that set a display mode, the palette and (for some) the hardware scroll, and fill the planes through the write format register with address-dependent patterns, so VRAM addressing, pixel order, colour mapping and the write/read logic all show in the picture:

| Test | Mode | What it checks |
|---|---|---|
| gfx640 | 640x200, 2 colours | plane I |
| gfx640h | 640x200, 4 colours | planes I and III (MZ-1R25) |
| gfx320h | 320x200, 16 colours | planes I-IV, palette group |
| gfx320b | 320x200, 4 colours, frame B | planes III and IV |
| gfx320x | 320x200, 4 colours, frame A | planes I and II |
| gfxwm | 320x200, 16 colours | EXOR, OR, RESET, REPLACE, PSET |
| gfxwm640 | 640x200, 4 colours | the same write modes |
| gfxrw | 320x200, 4 colours | RF single-plane read and colour search |
| gfxrw16 | 320x200, 16 colours | colour search with the RF frame bit 0 and 1 (all four planes compared) |
| gfxscr | 320x200 | full screen hardware scroll, CPU writes while scrolled |
| gfxscr640 | 640x200 | scroll window (SSA/SEA/SW) |

`compare_emu.sh` runs each in the simulation and in mz800emu (`--crop canvas`) and compares the pictures with `cmp_emu.py`; all match. `run_tests.sh` checks their frame hashes (`m800_*`).
