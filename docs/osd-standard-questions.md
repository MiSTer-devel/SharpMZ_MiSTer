# SharpMZ and the OSD standard: open questions

Reviewed 2026-10-24 against `~/dev2/osd-standard.md` and `~/dev2/tape-standard.md`. Decision for now: SharpMZ
keeps its own menu. These are the questions sent to the standard's author; the answers decide whether it moves over.

SharpMZ is one core for nine machines (MZ-80K, 80C, 80A, 1200, 80B, 2000, 700, 800, 1500), each with its own monitor
ROM, character set and media, with cassette, floppy and Quick Disk drives rather than SCSI disks.

1. **Device pages beyond P1-P5.** Tape (~10 rows), Floppy (4) and Printer (2 + a note) have no page in the standard.
   Reserve P6-P8 for core-specific device pages with fixed titles, or fold them into Advanced?
2. **Load ROM in a multi-machine core.** Rule 4: one top-page `F0,Load ROM`, not remembered. SharpMZ has a System
   ROM per model (so Load ROM means "the selected model's"), a CGROM and Load System RAM; System ROM and CGROM are
   remembered (`FC`) because testers want a replacement monitor back at every start. Main sends `FC` files before
   the saved status, so the core stages them for 3 s and then copies them to the model's slot. Is "not remembered"
   firm, with MGLs as the way to keep a ROM? Where do secondary firmware loads go (an MGL can't reach a sub-page)?
3. **Apply on reset vs the model selector.** Today a Model change resets at once and ejects the media. Should Model
   be an exception to rule 1, or should the core eject media at the reset that applies a new model?
4. **`Pri.` when the boot medium depends on the model.** Most models boot from tape; the MZ-800/1500 IPL offers
   tape, floppy or Quick Disk; the MZ-80B/2000 tries floppy, then tape. Is `Pri.` optional here?
5. **Hiding rows by model.** Many rows apply to one or two models (MZ-800 Mode/Border/RAM Disk, MZ-80B/2000 Boot
   Reset, VRAM Wait, Region). Can rows hidden by Model collapse instead of leaving a blank line each?
6. **Media that isn't a drive.** Load Direct to RAM (`F2`) loads a tape file into memory and starts it; MGLs use it,
   so it stays on the top page. Where in the media block?
7. **Memory and Network rows.** SharpMZ has neither; confirm nothing goes between the media and the submenus.
8. **Swap Alt/Win keys.** SharpMZ has a Keyboard Layout option (PC / Sharp) where Alt is GRPH on some models. Is
   Swap Alt/Win still required?
9. **Long names.** `MZ-80B/2000 Boot Reset`, `UART (mister_printerd)`, `3rd (CP/M 4.1 HD)` don't fit 16/11
   characters. Is a `-,` text row acceptable to explain an abbreviation?
10. **Names are the MGL interface.** Main's MGL `<option name= value=>` (Main_MiSTer e8e915a) matches the visible
    labels, so renaming a row or value breaks MGLs (not saved settings). Worth a line in rules 8/11.

Tape standard, for later: SharpMZ has Fast Tape (several factors) rather than `Tape speed` N x / Normal; no quick
start (no cartridge boot path; Tape Image Start: Direct writes RAM behind the firmware, which rule 173 says must not
be called quick start); Tape Messages / Tape Details instead of the `TAPE m:ss/m:ss` status bar; no mount info
message. Whether Fast Tape speeds only while the deck plays, and CPU and tape by the same factor, is to be checked.
