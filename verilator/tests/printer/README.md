# Printer test streams

Byte streams as the Sharp MZ sends them to its printer port, for the printer daemon (`mister_printerd`) and for
the core's printer bridge (`rtl/mz_printer.sv`, OSD Printer: UART).

| File | Made by | Contents |
|---|---|---|
| `prntest.mzf` | `make_prntest.py` | MZ-700/800 machine code that prints two text lines through the port (sim test `prn_mz700`, `prn_mz800`). |
| `hello_world_mz800.prn` | MZ-800 BASIC 1Z-016: `PRINT/P "HELLO WORLD"` | `HELLO WORLD` CR. Plain text. |
| `pen_test_mz800.prn` | MZ-800 BASIC 1Z-016: `PTEST`, `PRINT/P "PEN TEST DONE"` | `04` (pen test: the plotter draws a square in each of its four colours by itself), then a text line. |
| `plotter_demo_mz800.prn` | MZ-800 BASIC 1Z-016, the program below | Text, then MZ-1P16 / MZ-1P01 plotter graphics, then text: 544 bytes. |

Both `.prn` files were captured with mz800emu's printer capture (`--printer`, headless), MZ-800 with BASIC 1Z-016
from the year-based collection:

```sh
mz800emu --headless --model mz800 --mzf "BASIC 1Z-016.mzf" --mzf-direct --mzf-direct-frame 100 --printer \
         --type-rate 8:8 --type '300:...program, {WAIT 60} after each line...' --stop-at-frame 9000
```

The plotter demo program:

```basic
10 PRINT/P "SHARP MZ-800 PLOTTER TEST"
20 PRINT/P "TEXT MODE, THEN GRAPHICS"
30 PMODE GR
40 PCOLOR 0:PLINE 240,0,240,-240,0,-240,0,0
50 PCOLOR 1:PCIRCLE 120,-120,100
60 PCOLOR 2:PMOVE 0,-300:AXIS 0,-20,10:PMOVE 0,-300:AXIS 1,24,10
70 PCOLOR 3:PMOVE 20,-280:GPRINT "MISTER"
80 PHOME:PMODE TN
90 PRINT/P "DONE"
```

What the plotter receives (MZ-700 owner's manual, appendix A.6 "Color Plotter-Printer Control Codes"):

- Text mode: printable characters, CR (0D) ends a line. `01` = text mode, `02` = graphic mode, `03` = line up,
  `04` = pen test, `0A` = line feed, `0B`/`0C` = magnify / cancel, `0E` = back space, `0F` = form feed,
  `1D` = next colour, `09 09 09` / `09 09 0B` = reduce / cancel, `09 09 nnn 0D` = lines per page.
- Graphic mode: one ASCII command per line, each ended by CR:
  `Cn` pen 0-3 (black, blue, green, red), `Dx,y[,x,y...]` draw to (absolute), `Jx,y` draw relative,
  `Mx,y` move (pen up), `Rx,y` move relative, `Ln` line type (0 solid, 1-15 dotted), `Sn` character scale,
  `Qn` character direction, `Pcccc` print characters, `Xp,q,r` axis (p 0 = Y, 1 = X; q pitch, r count),
  `H` home, `I` set origin here, `A` back to text mode. Coordinates: X 0-480 across the paper, Y -999..999.
  BASIC's `PCIRCLE` arrives as a run of `D` segments.

In the demo: `02`, `C0`, four `D` lines (the square), `C1`, `M 220,-120` and about 40 `D` points (the circle),
`C2`, `M`, `X0,-20, 10`, `M`, `X1, 24, 10` (two axes), `C3`, `M 20,-280`, `PMISTER`, `H`, `0A 03 01` (back to text),
`DONE`.

The printer daemon (`printeremulation`, `-m sharpmz`, picked automatically for a core named SharpMZ) draws these
streams as an MZ-1P16 plotter would: four pen colours, round pen ends, text mode and graphic mode. The same three
files are its regression samples (`tests/samples/sharpmz_*.prn`, `make test`).

The plotter's own self-test (PAPER FEED held at power-on; mz800emu's plotter window, "Run drawing self-test") is
drawn by the plotter's 8050 firmware from its ROM: nothing crosses the printer port, so there is no stream for it.
`PTEST` (code 04) is the computer-side pen test.
