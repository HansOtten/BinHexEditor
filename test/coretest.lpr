program coretest;

{
  BinHexEditor - console tests of the core units (no GUI):
  - export/import round trip of every format through the Convert8bithex
    units
  - import keeps bytes outside the imported data intact
  - undo/redo, insert/delete, resize
  - search and checksum

  Build: fpc -Fu../src -Fu../hexunits -FUlib coretest.lpr
}

{$mode objfpc}{$H+}

uses
  SysUtils, editbuffer, importexport, searching, hexglobals;

var
  failures : integer = 0 ;
  tests    : integer = 0 ;
  tmpdir   : string ;

procedure Check(cond : boolean ; const what : string) ;
begin
  inc(tests) ;
  if not cond
    then
      begin
        inc(failures) ;
        writeln('FAIL: ', what) ;
      end ;
end ;

procedure FillRandom(buf : TEditBuffer ; offset, count : integer) ;
var
  i : integer ;
begin
  buf.BeginChange(offset, count, 'test') ;
  for i := offset to offset + count - 1 do
    buf.RawSetByte(i, Random(256)) ;
  buf.EndChange ;
end ;

function SameRange(a : TEditBuffer ; aofs : integer ; b : TEditBuffer ;
                   bofs, count : integer) : boolean ;
var
  i : integer ;
begin
  Result := true ;
  for i := 0 to count - 1 do
    if a[aofs + i] <> b[bofs + i]
      then
        exit(false) ;
end ;

procedure TestRoundTrip(fmt : THexFormat ; startofs, len, fileaddr : integer) ;
var
  src, dst : TEditBuffer ;
  p        : TExportParams ;
  msg      : string ;
  r        : TImportResult ;
  name     : string ;
  i, chk   : integer ;
begin
  name := Format('%s ofs %.5X len %d addr %.4X',
                 [FormatKeys[fmt], startofs, len, fileaddr]) ;
  src := TEditBuffer.Create ;
  dst := TEditBuffer.Create ;
  try
    src.NewBuffer(128*KB) ;
    FillRandom(src, 0, src.Size) ;
    p.Format := fmt ;
    p.FileName := tmpdir + 'rt_' + FormatKeys[fmt] + '.out' ;
    p.StartOffset := startofs ;
    p.EndOffset := startofs + len - 1 ;
    p.FileAddress := fileaddr ;
    p.TapeID := 1 ;
    p.DefineText := '.byte $' ;
    p.S9Address := fileaddr ;
    msg := ExportRange(src, p) ;
    Check(msg = '', name + ' export: ' + msg) ;
    if (msg <> '') or not CanImport(fmt)
      then
        exit ;
    { import at file address into a buffer with a known pattern }
    dst.NewBuffer(64*KB) ;
    dst.Fill(0, dst.Size, $5A) ;
    if HasNoAddress(fmt)
      then
        r := ImportFile(dst, fmt, p.FileName, ipOffset, $100, 0)
      else
        r := ImportFile(dst, fmt, p.FileName, ipFileAddress, 0, 0) ;
    Check(r.Ok, name + ' import: ' + r.Message) ;
    if not r.Ok
      then
        exit ;
    if HasNoAddress(fmt)
      then
        chk := $100
      else
        chk := fileaddr ;
    Check(r.FirstOffset = chk, name + Format(' first offset %X expected %X',
                                            [r.FirstOffset, chk])) ;
    Check(r.LastOffset = chk + len - 1, name +
          Format(' last offset %X expected %X', [r.LastOffset, chk + len - 1])) ;
    Check(SameRange(src, startofs, dst, chk, len), name + ' data differs') ;
    { bytes around the import untouched }
    if chk > 0
      then
        Check(dst[chk - 1] = $5A, name + ' byte before import changed') ;
    if chk + len < 64*KB
      then
        Check(dst[chk + len] = $5A, name + ' byte after import changed') ;
    { undo restores the pattern }
    dst.Undo ;
    i := 0 ;
    while (i < dst.Size) and (dst[i] = $5A) do
      inc(i) ;
    Check(i = dst.Size, name + ' undo of import incomplete') ;
  finally
    src.Free ;
    dst.Free ;
  end ;
end ;

procedure TestMultipartGap ;
var
  f   : TextFile ;
  fn  : string ;
  buf : TEditBuffer ;
  r   : TImportResult ;
begin
  { Intel hex with two parts: 2 bytes at $0010, 2 bytes at $0020 }
  fn := tmpdir + 'gap.hex' ;
  AssignFile(f, fn) ;
  Rewrite(f) ;
  writeln(f, ':020010001122BB') ;
  writeln(f, ':02002000334467') ;
  writeln(f, ':00000001FF') ;
  CloseFile(f) ;
  buf := TEditBuffer.Create ;
  try
    buf.Fill(0, buf.Size, $5A) ;
    r := ImportFile(buf, hfIntel, fn, ipOffset, $1000, 0) ;
    Check(r.Ok, 'gap import: ' + r.Message) ;
    Check(r.Parts = 2, 'gap import parts = ' + IntToStr(r.Parts)) ;
    Check((buf[$1000] = $11) and (buf[$1001] = $22), 'gap part 1') ;
    Check((buf[$1010] = $33) and (buf[$1011] = $44), 'gap part 2') ;
    Check((buf[$1002] = $5A) and (buf[$100F] = $5A), 'gap bytes untouched') ;
  finally
    buf.Free ;
  end ;
end ;

procedure TestBigBinAndBase ;
var
  buf : TEditBuffer ;
  data : TBytes ;
  msg, fn : string ;
  r : TImportResult ;
  i : integer ;
  p : TExportParams ;
begin
  { BIN of 100K: own routine, buffer grows to 128K }
  SetLength(data, 100*KB) ;
  for i := 0 to Length(data) - 1 do
    data[i] := i and $FF ;
  fn := tmpdir + 'big.bin' ;
  Check(WriteBinFile(fn, data[0], Length(data), msg), 'write big bin ' + msg) ;
  buf := TEditBuffer.Create ;
  try
    r := ImportFile(buf, hfBIN, fn, ipOffset, 0, 0) ;
    Check(r.Ok and (buf.Size = 128*KB), 'big bin import, size ' +
          IntToStr(buf.Size) + ' ' + r.Message) ;
    Check(buf[100*KB - 1] = ((100*KB - 1) and $FF), 'big bin data') ;
    { export range > 64K as Intel hex refused, as BIN ok }
    p.Format := hfIntel ;
    p.FileName := tmpdir + 'x.hex' ;
    p.StartOffset := 0 ;
    p.EndOffset := 70000 ;
    p.FileAddress := 0 ;
    Check(CheckExport(buf, p) <> '', 'intel > 64K must be refused') ;
    p.Format := hfBIN ;
    Check(CheckExport(buf, p) = '', 'bin > 64K must be allowed') ;
    { import at file address with base address $E000 }
    buf.NewBuffer(8*KB) ;
    p.Format := hfIntel ;
    p.StartOffset := 0 ;
    p.EndOffset := $FF ;
    p.FileAddress := $E000 ;
    buf.Fill(0, $100, $42) ;
    Check(ExportRange(buf, p) = '', 'export at E000') ;
    buf.NewBuffer(8*KB) ;
    r := ImportFile(buf, hfIntel, p.FileName, ipFileAddress, 0, $E000) ;
    Check(r.Ok and (r.FirstOffset = 0) and (buf[$FF] = $42) and
          (buf[$100] = $FF), 'import with base E000: ' + r.Message) ;
    r := ImportFile(buf, hfIntel, p.FileName, ipFileAddress, 0, $F000) ;
    Check(not r.Ok, 'import below base must be refused') ;
  finally
    buf.Free ;
  end ;
end ;

procedure TestEditing ;
var
  buf : TEditBuffer ;
  i : integer ;
begin
  buf := TEditBuffer.Create ;
  try
    buf.NewBuffer(2*KB) ;
    for i := 0 to 9 do
      buf.SetByte(i, i) ;
    Check(buf[9] = 9, 'setbyte') ;
    Check(buf.Modified, 'modified') ;
    buf.Undo ;
    Check(buf[9] = $FF, 'undo setbyte') ;
    buf.Redo ;
    Check(buf[9] = 9, 'redo setbyte') ;
    { delete moves rest down, empty byte at end }
    buf.SetByte(2*KB - 1, $77) ;
    buf.Delete(0, 1) ;
    Check((buf[0] = 1) and (buf[2*KB - 2] = $77) and (buf[2*KB - 1] = $FF),
          'delete') ;
    buf.Undo ;
    Check((buf[0] = 0) and (buf[2*KB - 1] = $77), 'undo delete') ;
    { insert session as one undo step }
    buf.BeginChange(3, buf.Size - 3, 'Insert') ;
    buf.RawInsert(3, 1) ;
    buf.RawSetByte(3, $AA) ;
    buf.RawInsert(4, 1) ;
    buf.RawSetByte(4, $BB) ;
    buf.EndChange ;
    Check((buf[3] = $AA) and (buf[4] = $BB) and (buf[5] = 3), 'insert') ;
    buf.Undo ;
    Check((buf[3] = 3) and (buf[4] = 4) and (buf[2*KB - 1] = $77),
          'undo insert') ;
    { resize }
    buf.Resize(4*KB) ;
    Check((buf.Size = 4*KB) and (buf[4*KB - 1] = $FF), 'grow') ;
    buf.Resize(2*KB) ;
    buf.Resize(KB) ;     { not a list size, but allowed by the class }
    buf.Undo ;
    Check((buf.Size = 2*KB) and (buf[2*KB - 1] = $77), 'undo shrink') ;
    { undo depth }
    for i := 1 to 15 do
      buf.SetByte(100, i) ;
    i := 0 ;
    while buf.CanUndo do
      begin
        buf.Undo ;
        inc(i) ;
      end ;
    Check(i = MaxUndo, 'undo depth ' + IntToStr(i)) ;
    Check(RoundUpBufferSize(65537) = 128*KB, 'roundup') ;
    Check(RoundUpBufferSize(MaxBufferSize + 1) = -1, 'roundup > 1M') ;
  finally
    buf.Free ;
  end ;
end ;

procedure TestSearch ;
var
  data : TBytes ;
  spec : TSearchSpec ;
  w : boolean ;
  b : byte ;
begin
  SetLength(data, 64) ;
  FillChar(data[0], 64, 0) ;
  data[10] := $4C ; data[11] := $00 ; data[12] := $1C ;
  data[40] := ord('H') or $80 ; data[41] := ord('e') ; data[42] := ord('L') ;
  spec := Default(TSearchSpec) ;
  spec.RangeStart := 0 ;
  spec.RangeEnd := 63 ;
  spec.Wrap := true ;
  spec.Kind := skHexBytes ;
  spec.Text := '4c001c' ;
  Check(ParsePattern(spec) = '', 'parse hex bytes') ;
  Check(SearchData(@data[0], spec, 0, w) = 10, 'find hex bytes') ;
  Check((SearchData(@data[0], spec, 11, w) = 10) and w, 'find with wrap') ;
  spec.Wrap := false ;
  Check(SearchData(@data[0], spec, 11, w) = -1, 'not found without wrap') ;
  spec.Kind := skHexWords ;
  spec.Text := '1C00' ;
  Check(ParsePattern(spec) = '', 'parse hex word') ;
  Check(SearchData(@data[0], spec, 0, w) = 11, 'find hex word low first') ;
  spec.Text := '0000 0000 0000 0000 0000 0000 0000 0000 0000' ;
  Check(ParsePattern(spec) <> '', 'too many words') ;
  spec.Kind := skText ;
  spec.Text := 'hel' ;
  Check(ParsePattern(spec) = '', 'parse text') ;
  Check(SearchData(@data[0], spec, 0, w) = -1, 'text with bit 7 not found') ;
  spec.IgnoreBit7 := true ;
  Check(SearchData(@data[0], spec, 0, w) = 40, 'text ignore bit 7') ;
  spec.CaseSensitive := true ;
  Check(SearchData(@data[0], spec, 0, w) = -1, 'case sensitive') ;
  spec.CaseSensitive := false ;
  spec.Backward := true ;
  Check(SearchData(@data[0], spec, 63, w) = 40, 'backward') ;
  { checksums }
  data := TBytes.Create(ord('1'), ord('2'), ord('3'), ord('4'), ord('5'),
                        ord('6'), ord('7'), ord('8'), ord('9')) ;
  Check(CRC32(@data[0], 9) = $CBF43926, 'crc32 check value') ;
  Check(Checksum16(@data[0], 9) = $01DD, 'sum16') ;
  Check(ParseByteValue('''A''', b) and (b = 65), 'byte char') ;
  Check(ParseByteValue('$ff', b) and (b = 255), 'byte hex') ;
  Check(not ParseByteValue('100', b), 'byte too big') ;
end ;

var
  f : THexFormat ;
begin
  Randomize ;
  tmpdir := IncludeTrailingPathDelimiter(GetTempDir) + 'bhetest' +
            PathDelim ;
  ForceDirectories(tmpdir) ;
  for f := Low(THexFormat) to High(THexFormat) do
    begin
      TestRoundTrip(f, $1234, 1000, $0200) ;
      TestRoundTrip(f, $10000, 257, $E000) ;   { range above 64K }
      TestRoundTrip(f, 0, 1, $FFFF) ;           { one byte at the top }
    end ;
  TestRoundTrip(hfIntel, 0, $10000, 0) ;        { full 64K }
  TestRoundTrip(hfBIN, 0, $10000, 0) ;
  TestMultipartGap ;
  TestBigBinAndBase ;
  TestEditing ;
  TestSearch ;
  writeln(tests, ' checks, ', failures, ' failures') ;
  if failures > 0
    then
      Halt(1) ;
end.
