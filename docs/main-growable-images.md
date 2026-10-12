# Proposal: growable image slots in Main_MiSTer

Status: draft for discussion with the MiSTer maintainers. Nothing here is implemented.

## Why

SharpMZ's **Tape Image** slot (`S0,MZTMZF,Tape Image`) holds an MZT: MZF records back to back. When the
machine SAVEs, `rtl/tape_image.sv` appends the new record after the last one. A file mounted through an `S` entry
cannot grow, so today the user has to mount a pre-made zero-filled blank tape (`tools/make_blank_tape.py`, 1 MB),
and the core reports the tape as full when that space runs out.

Main already knows how to grow an image ("that is how saves work"); it just only allows it for save files.

## What Main does today (upstream MiSTer-devel, `user_io.cpp` / `menu.cpp` / `file_io.cpp`)

- Each mounted image has `sd_image_cangrow[index]`, set by `user_io_file_mount(name, index, pre)` as `pre != 0`.
- SD write handling (`user_io_poll`, `op == 2`): a write is accepted when `lba <= size / blksz`, i.e. anywhere inside
  the file or at the first sector past its end. Without `cangrow` the length is clipped to the bytes remaining, so a
  write at the end writes nothing. With `cangrow` the whole sector is written; `FileWriteAdv` updates `size`, so the next
  sector can append again and the file keeps growing.
- If the image doesn't exist yet (`sd_image[disk].type == 2`), a write to LBA 0 creates it.
- The only caller that passes `pre = 1` is `user_io_file_tx` with `opensave`: an `FS<n>,EXT,...` entry loads a file,
  then Main mounts `saves/<core>/<name>.sav` on slot 0 with grow enabled.
- Every `S` mount (`menu.cpp`, `MENU_GENERIC_IMAGE_SELECTED`: `user_io_file_mount(selPath, ioctl_index)`; also the
  recent-files / auto-mount paths in `user_io.cpp`) passes `pre = 0`.

So growth works, but only for one slot (0), with a name derived from another file, in `saves/`.

## Proposed change

A CONF_STR flag on `S` entries that asks for the mounted image to be growable, next to the existing `C` (store name)
flag:

```
SG0,MZTMZF,Tape Image;      // G: writes may append past the end of the file
SCG1,DSK,Disk;              // flags combine
```

Main changes, all small:

1. `menu.cpp`, `S` entry parsing (where `SC` is handled): accept `G` after `S`/`C` and remember it per slot
   (e.g. `grow_slot[ioctl_index] = 1`).
2. `menu.cpp`, `MENU_GENERIC_IMAGE_SELECTED`: `user_io_file_mount(selPath, ioctl_index, grow_slot[ioctl_index] ? 1 : 0)`.
   Note that `pre` also feeds `use_save` for slot 0 (`if (!index ...) use_save = pre;`), which makes writes call
   `menu_process_save()`. Either keep that (harmless: it only arms the save timer) or pass the grow request as a
   separate argument so `use_save` stays 0 for a plain image.
3. The other places that mount `S` slots (recent files, `user_io.cpp` auto-mount on core load, MGL `type="s"`) should
   use the same flag so the behaviour doesn't depend on how the image was mounted. The MGL matcher in `menu.cpp`
   (`if (p[idx] == 'S') idx++; if (p[idx] == 'C') idx++;`) must also skip `G`, or `SG0` entries won't match.
4. The CONF_STR parser elsewhere (`user_io_get_confstr` users, e.g. `user_io_ext_idx` / index extraction) must skip
   the new letter the same way it skips `C`.

Nothing changes for cores that don't use `G`.

Older Main versions (no `G` support): the entry still has to mount. A Main that doesn't know `G` reads `SG0` as an
`S` entry with a non-digit index, so a core that wants to stay compatible should keep a plain `S0` entry until the
change is released, or Main could accept `G` *after* the index (`S0G,...`) if that parses more safely in old versions.
This needs checking against the old parsers before picking the syntax.

## What the core does once Main supports it

`rtl/tape_image.sv`:

- Track the image size itself: `img_size` is only sent at mount time and Main doesn't resend it as the file grows.
- When saving, append at the end of the recorded area as now, but don't stop at `size`: write the sector(s) past the
  end and update the internal size. Records are written as whole 512-byte sectors (read-modify-write through the
  sector cache), so the file grows in 512-byte steps; the zero padding after the last record already reads as end of
  tape (attribute 00).
- `tape_full` only applies to images mounted without grow (old Main, or a read-only file).
- Accept an empty writable image (size 0) as a mounted tape, so a new file works too (Main would need the `type == 2`
  "create on first write" path for `S` mounts as well, or the user creates an empty file).

Until then the blank-tape approach keeps working, and growing writes on an old Main are simply clipped (the record is
lost, as now when the blank tape is full).

## Alternative that works today (RTL only)

Make **Load Tape to CMT** an `FS1,MZF,...` entry. After loading `GAME.mzf`, Main mounts `saves/SharpMZ/GAME.sav` on
slot 0, which is the tape image slot, with grow enabled. `tape_image.sv` would accept the empty writable image and
append past the end; the Tape Image entry would add `SAV` to its extensions so a saved tape can be mounted again.
Downsides: the save file is named after whatever tape was loaded last and replaces the mounted tape image, and there is
no way to start an empty save tape without loading a file first.
