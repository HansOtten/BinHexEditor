unit importexport;

{
  BinHexEditor - import and export through the Convert8bithex units

  The units loadhexformats/savehexformats work on hexglobals.buffer, a
  64K window with 16 bit addresses. Import loads a file into the window
  and copies every part separately into the edit buffer; export copies a
  range of the edit buffer into the window and calls the save procedure.

  BIN files are read/written by this unit itself (any size up to 1M),
  BIN import up to 64K goes through loadBINfile as specified.

  No GUI code, so the unit is also used by the console tests.

  MIT License, Copyright (c) 2026 Hans Otten
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, editbuffer;

type
  THexFormat = (hfBIN, hfPRG, hfHex, hfIntel, hfMOS, hfTIM, hfSrec,
                hfApple1, hfKIM, hfDefine) ;

  TImportPosition = (ipFileAddress, ipOffset) ;

  TImportResult = record
    Ok          : boolean ;
    Message     : string ;
    FirstOffset : integer ;   { lowest offset written }
    LastOffset  : integer ;   { highest offset written }
    Parts       : integer ;
    Grown       : boolean ;   { buffer size was increased }
  end ;

  TExportParams = record
    Format      : THexFormat ;
    FileName    : string ;
    StartOffset : integer ;
    EndOffset   : integer ;
    FileAddress : integer ;
    TapeID      : byte ;      { KIM tape }
    DefineText  : string ;    { Define }
    S9Address   : integer ;   { Motorola S-record }
  end ;

const
  FormatNames : array[THexFormat] of string =
    ('BIN (binary)', 'PRG (binary with load address)', 'Hex (plain)',
     'Intel hex', 'MOS papertape', 'TIM papertape', 'Motorola S-record',
     'Apple 1 hex', 'KIM-1 tape', 'Define (assembler source)') ;
  FormatKeys : array[THexFormat] of string =
    ('BIN', 'PRG', 'HEX', 'INTEL', 'MOS', 'TIM', 'SREC', 'APPLE1', 'KIM',
     'DEFINE') ;
  FormatFilters : array[THexFormat] of string =
    ('Binary files (*.bin;*.rom)|*.bin;*.rom|',
     'PRG files (*.prg)|*.prg|',
     'Hex files (*.hex;*.txt)|*.hex;*.txt|',
     'Intel hex files (*.hex;*.ihx;*.ihex)|*.hex;*.ihx;*.ihex|',
     'Papertape files (*.ptp;*.pap)|*.ptp;*.pap|',
     'Papertape files (*.ptp;*.pap;*.tim)|*.ptp;*.pap;*.tim|',
     'S-record files (*.s19;*.srec;*.mot)|*.s19;*.srec;*.mot|',
     'Apple 1 hex files (*.txt;*.hex)|*.txt;*.hex|',
     'KIM tape files (*.kim;*.bin)|*.kim;*.bin|',
     'Assembler source (*.asm;*.a65;*.inc)|*.asm;*.a65;*.inc|') ;
  AllFilesFilter = 'All files (*.*)|*.*' ;

{ formats that can be imported (Define has no loader) }
function CanImport(f : THexFormat) : boolean ;
{ formats without an address in the file }
function HasNoAddress(f : THexFormat) : boolean ;
function FormatFromKey(const key : string ; default : THexFormat) : THexFormat ;

{ BIN file <-> bytes, any size up to MaxBufferSize }
function ReadBinFile(const filename : string ; out data : TBytes ;
                     out msg : string) : boolean ;
function WriteBinFile(const filename : string ; const data ; count : integer ;
                      out msg : string) : boolean ;

{ import file into edit buffer as one undo step.
  position ipFileAddress: offset = address in file - baseaddress
  position ipOffset     : lowest address goes to atoffset }
function ImportFile(buf : TEditBuffer ; fmt : THexFormat ;
                    const filename : string ; position : TImportPosition ;
                    atoffset, baseaddress : integer) : TImportResult ;

{ check export parameters, '' if ok }
function CheckExport(buf : TEditBuffer ; const p : TExportParams) : string ;
{ export range; '' if ok, otherwise error message }
function ExportRange(buf : TEditBuffer ; const p : TExportParams) : string ;

implementation

uses
  hexglobals, loadhexformats, savehexformats ;

function CanImport(f : THexFormat) : boolean ;
begin
  Result := f <> hfDefine ;
end ;

function HasNoAddress(f : THexFormat) : boolean ;
begin
  Result := f in [hfBIN, hfHex] ;
end ;

function FormatFromKey(const key : string ; default : THexFormat) : THexFormat ;
var
  f : THexFormat ;
begin
  for f := Low(THexFormat) to High(THexFormat) do
    if SameText(FormatKeys[f], key)
      then
        exit(f) ;
  Result := default ;
end ;

function ReadBinFile(const filename : string ; out data : TBytes ;
                     out msg : string) : boolean ;
var
  fs : TFileStream ;
begin
  Result := false ;
  data := nil ;
  msg := '' ;
  try
    fs := TFileStream.Create(filename, fmOpenRead or fmShareDenyWrite) ;
    try
      if fs.Size > MaxBufferSize
        then
          begin
            msg := Format('File is too big (%d bytes), maximum is 1M',
                          [fs.Size]) ;
            exit ;
          end ;
      SetLength(data, fs.Size) ;
      if fs.Size > 0
        then
          fs.ReadBuffer(data[0], fs.Size) ;
      Result := true ;
    finally
      fs.Free ;
    end ;
  except
    on E: Exception do
      msg := 'Error reading ' + filename + ': ' + E.Message ;
  end ;
end ;

function WriteBinFile(const filename : string ; const data ; count : integer ;
                      out msg : string) : boolean ;
var
  fs : TFileStream ;
begin
  Result := false ;
  msg := '' ;
  try
    fs := TFileStream.Create(filename, fmCreate) ;
    try
      if count > 0
        then
          fs.WriteBuffer(data, count) ;
      Result := true ;
    finally
      fs.Free ;
    end ;
  except
    on E: Exception do
      msg := 'Error writing ' + filename + ': ' + E.Message ;
  end ;
end ;

function FileSizeOf(const filename : string) : int64 ;
var
  sr : TSearchRec ;
begin
  Result := -1 ;
  if FindFirst(filename, faAnyFile, sr) = 0
    then
      Result := sr.Size ;
  FindClose(sr) ;
end ;

{ call the loader of the unit, true if loaded }
function LoadWindow(fmt : THexFormat ; const filename : string ;
                    out msg : string) : boolean ;
begin
  Result := false ;
  msg := '' ;
  Initbuffer($00) ;
  startaddress := 0 ;
  endaddress := 0 ;
  hloaded := false ;
  exitreason := '' ;
  if not OpenLoadFile(filename)
    then
      begin
        msg := exitreason ;
        exit ;
      end ;
  try
    try
      case fmt of
        hfBIN    : loadBINfile ;
        hfPRG    : loadPRGfile ;
        hfHex    : loadhexfile ;
        hfIntel  : loadIntelhexfile ;
        hfMOS    : loadMOSpapertape ;
        hfTIM    : loadTIMpapertape ;
        hfSrec   : loadMotorolaSrec ;
        hfApple1 : loadApple1hex ;
        hfKIM    : loadKIMtape ;
      end ;
    except
      on E: EInOutError do
        begin
          hloaded := false ;
          exitreason := 'Unexpected end of file or read error (' +
                        E.Message + ')' ;
        end ;
    end ;
  finally
    CloseLoadFile ;
  end ;
  if not hloaded
    then
      begin
        msg := exitreason ;
        if msg = ''
          then
            msg := 'File could not be loaded as ' + FormatNames[fmt] ;
        exit ;
      end ;
  if not ValidateBufferparts
    then
      begin
        msg := exitreason ;
        exit ;
      end ;
  Result := true ;
end ;

function ImportFile(buf : TEditBuffer ; fmt : THexFormat ;
                    const filename : string ; position : TImportPosition ;
                    atoffset, baseaddress : integer) : TImportResult ;
var
  data       : TBytes ;
  msg        : string ;
  i, lowaddr,
  highaddr,
  shift,
  needed,
  newsize,
  count,
  oldsize    : integer ;
  ownbin     : boolean ;
  fsize      : int64 ;
begin
  Result.Ok := false ;
  Result.Message := '' ;
  Result.FirstOffset := 0 ;
  Result.LastOffset := -1 ;
  Result.Parts := 0 ;
  Result.Grown := false ;
  if not CanImport(fmt)
    then
      begin
        Result.Message := FormatNames[fmt] + ' can not be imported' ;
        exit ;
      end ;
  if not FileExists(filename)
    then
      begin
        Result.Message := 'File not found: ' + filename ;
        exit ;
      end ;

  { BIN/PRG: check the size first }
  ownbin := false ;
  if fmt in [hfBIN, hfPRG]
    then
      begin
        fsize := FileSizeOf(filename) ;
        if fmt = hfPRG
          then
            fsize := fsize - 2 ;
        if fsize > WindowSize
          then
            begin
              if fmt = hfPRG
                then
                  begin
                    Result.Message := 'PRG file is bigger than 64K' ;
                    exit ;
                  end ;
              ownbin := true ;
            end ;
        if fsize <= 0
          then
            begin
              Result.Message := 'No data found in file' ;
              exit ;
            end ;
      end ;

  if ownbin
    then
      begin
        if not ReadBinFile(filename, data, msg)
          then
            begin
              Result.Message := msg ;
              exit ;
            end ;
        { treat as one part at address 0 }
        lowaddr := 0 ;
        highaddr := Length(data) - 1 ;
        Result.Parts := 1 ;
      end
    else
      begin
        if not LoadWindow(fmt, filename, msg)
          then
            begin
              Result.Message := msg ;
              exit ;
            end ;
        lowaddr := bufferparts[1].bufferstart ;
        highaddr := bufferparts[1].bufferend ;
        for i := 2 to buffers_inuse do
          begin
            if bufferparts[i].bufferstart < lowaddr
              then
                lowaddr := bufferparts[i].bufferstart ;
            if bufferparts[i].bufferend > highaddr
              then
                highaddr := bufferparts[i].bufferend ;
          end ;
        Result.Parts := buffers_inuse ;
      end ;

  { where does it go }
  if position = ipOffset
    then
      shift := atoffset - lowaddr
    else
      if HasNoAddress(fmt)
        then
          shift := 0
        else
          shift := -baseaddress ;
  if lowaddr + shift < 0
    then
      begin
        Result.Message := Format('Data starts at address $%.4X, below the ' +
                                 'base address $%.4X',
                                 [lowaddr, baseaddress]) ;
        exit ;
      end ;
  needed := highaddr + shift + 1 ;
  oldsize := buf.Size ;
  newsize := oldsize ;
  if needed > oldsize
    then
      begin
        newsize := RoundUpBufferSize(needed) ;
        if newsize < 0
          then
            begin
              Result.Message := 'Imported data does not fit in 1M' ;
              exit ;
            end ;
        Result.Grown := true ;
      end ;

  { one undo step covering all written bytes (and growth) }
  if newsize > oldsize
    then
      buf.BeginChange(lowaddr + shift, newsize - (lowaddr + shift), 'Import')
    else
      buf.BeginChange(lowaddr + shift, highaddr - lowaddr + 1, 'Import') ;
  if newsize > oldsize
    then
      buf.RawResize(newsize) ;
  if ownbin
    then
      buf.RawWrite(shift, data[0], Length(data))
    else
      for i := 1 to buffers_inuse do
        with bufferparts[i] do
          begin
            count := bufferend - bufferstart + 1 ;
            buf.RawWrite(bufferstart + shift, buffer[bufferstart], count) ;
          end ;
  buf.EndChange ;

  Result.FirstOffset := lowaddr + shift ;
  Result.LastOffset := highaddr + shift ;
  Result.Ok := true ;
  Result.Message := Format('Imported %s: offset %.5X - %.5X (%d bytes)',
                           [ExtractFileName(filename), Result.FirstOffset,
                            Result.LastOffset,
                            Result.LastOffset - Result.FirstOffset + 1]) ;
  if Result.Parts > 1
    then
      Result.Message := Result.Message +
                        Format(', %d parts', [Result.Parts]) ;
  if Result.Grown
    then
      Result.Message := Result.Message + ', buffer size now ' +
                        BufferSizeText(buf.Size) ;
end ;

function CheckExport(buf : TEditBuffer ; const p : TExportParams) : string ;
var
  len : integer ;
begin
  Result := '' ;
  if p.FileName = ''
    then
      exit('No file name given') ;
  if (p.StartOffset < 0) or (p.StartOffset >= buf.Size)
    then
      exit('Start offset outside the buffer') ;
  if (p.EndOffset < p.StartOffset) or (p.EndOffset >= buf.Size)
    then
      exit('End offset must be between start offset and end of buffer') ;
  if p.Format = hfBIN
    then
      exit ;   { own routine, any length, no address }
  len := p.EndOffset - p.StartOffset + 1 ;
  if len > WindowSize
    then
      exit('Range is bigger than 64K; only BIN can export more') ;
  if (p.FileAddress < 0) or (p.FileAddress + len - 1 > $FFFF)
    then
      exit(Format('File address $%.4X + length $%X goes beyond $FFFF',
                  [p.FileAddress, len])) ;
  if (p.Format = hfSrec) and ((p.S9Address < 0) or (p.S9Address > $FFFF))
    then
      exit('S9 start address must be $0000-$FFFF') ;
  if (p.Format = hfDefine) and (p.DefineText = '')
    then
      exit('No define directive given') ;
end ;

function ExportRange(buf : TEditBuffer ; const p : TExportParams) : string ;
var
  len : integer ;
  msg : string ;
begin
  Result := CheckExport(buf, p) ;
  if Result <> ''
    then
      exit ;
  len := p.EndOffset - p.StartOffset + 1 ;
  if p.Format = hfBIN
    then
      begin
        if not WriteBinFile(p.FileName, buf.DataPtr[p.StartOffset], len, msg)
          then
            Result := msg ;
        exit ;
      end ;

  Initbuffer(buf.EmptyByte) ;
  Move(buf.DataPtr[p.StartOffset], buffer[p.FileAddress], len) ;
  SetSinglePart(p.FileAddress, p.FileAddress + len - 1) ;
  SplitSaveFilename(p.FileName) ;
  CloseSaveFile ;
  saved := false ;
  exitreason := '' ;
  try
    try
      case p.Format of
        hfPRG    : SavePRGfile ;
        hfHex    : savehexfile ;
        hfIntel  : saveIntelhexfile ;
        hfMOS    : saveMOSpapertape ;
        hfTIM    : saveTIMpapertape ;
        hfSrec   : begin
                     startaddress := p.S9Address ;
                     saveMotorolaSrec ;
                   end ;
        hfApple1 : saveApple1Hex ;
        hfKIM    : saveKIMtape(p.TapeID) ;
        hfDefine : saveDefineType(p.DefineText) ;
      end ;
    except
      on E: EInOutError do
        begin
          saved := false ;
          exitreason := 'Error writing ' + p.FileName + ': ' + E.Message ;
        end ;
    end ;
  finally
    CloseSaveFile ;
  end ;
  if not saved
    then
      begin
        Result := exitreason ;
        if Result = ''
          then
            Result := 'Error writing ' + p.FileName ;
      end ;
end ;

end.
