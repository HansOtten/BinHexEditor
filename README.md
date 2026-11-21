# BinHexEditor


Import, edit and export the data of a data buffer in binary form.
Perfect for manipulating E(E)PROM contents.

A Lazarus / Free Pascal GUI hex editor for binary files like EPROM images of 2K .. 1M
, with import and export of the 8 bit hex formats BIN, PRG, hex, Intel hex, MOS papertape, TIM papertape,
Motorola S-record, Apple 1 hex, KIM-1 tape and Define (assembler source).

## Features

- Grid with address, 16 or 32 hex bytes and ASCII per row; base address
  for display (e.g. E000 for a ROM)
- Overwrite and insert editing in the hex and the ASCII part, delete,
  fill, copy/paste as hex text, undo/redo 10 deep
- Load/Save BIN of the whole buffer (up to 1M)
- Import any supported format at the address in the file or at an
  offset; only the bytes in the file are written
- Export the selection in any supported format (up to 64K, 16 bit file
  address; BIN any size)
- Find hex bytes, hex words (low byte first) or ASCII text
- Checksum (16 bit sum, CRC32), go to, settings in an ini file

## Building

Open `BinHexEditor.lpi` in Lazarus and build, or:

    lazbuild BinHexEditor.lpi

Range and overflow checking must stay off (set in the project): the
Convert8bithex units depend on byte wrap around.

## Folders

| Folder     | Contents |
|------------|----------|
| `src`      | editor units and forms |
| `hexunits` | `loadhexformats`, `savehexformats` (unchanged Convert8bithex units) and `hexglobals` V1.1 |
| `test`     | console test of the core units (round trip of all formats, undo, search) |
| `docs`     | specification |

## License

MIT License, Copyright (c) 2026 Hans Otten
