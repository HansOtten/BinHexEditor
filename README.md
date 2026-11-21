# BinHexEditor

Import, edit and export the data of a data buffer in binary form.

A Lazarus / Free Pascal GUI hex editor for EPROM images of 2K .. 1M
(2716 .. 27C080), with import and export of the 8 bit hex formats of
Convert8bithex: BIN, PRG, hex, Intel hex, MOS papertape, TIM papertape,
Motorola S-record, Apple 1 hex, KIM-1 tape and Define (assembler source).

See [docs/design_of_BinHexEditor.txt](docs/design_of_BinHexEditor.txt) for
the specification.

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

`hexglobals` V1.1 is compatible with V1.0: the window buffer has 256 bytes
of slack after $FFFF and there are some helper routines. It can replace
the copy in convert8bithex.

## Tests

    cd test
    fpc -Fu../src -Fu../hexunits -FUlib coretest.lpr
    ./coretest

## License

MIT License, Copyright (c) 2026 Hans Otten
