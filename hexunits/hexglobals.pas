unit hexglobals;

{
  Shared state for the hex format load/save units, without any GUI.
  Replaces the variable/const part of the Lazarus unit mainconvert,
  so loadhexformats and savehexformats can be used by the command line
  program (and by the GUI, if mainconvert uses this unit).

  V1.1 November 2026 (for BinHexEditor, compatible with V1.0)
       - buffer has WindowSlack extra bytes after $FFFF, so a loader that
         runs past $FFFF (no bounds check in the loaders) does not
         overwrite bufferparts and the other variables
       - helpers OpenLoadFile, CloseLoadFile, CloseSaveFile,
         ValidateBufferparts, SetSinglePart

  MIT License, Copyright (c) 2019-2026 Hans Otten
}

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  versiontext  = 'convert8bithex - convert 8 bit hex files, command line V1.0 (based on Convert 8 bit hex files V3.1) Hans Otten' ;

  maxbuf = 64 ; { maximum number of multiparts in file }
  CR = $0D ;
  LF = $0A ;

  WindowSize  = $10000 ; { address space the load/save units work in }
  WindowSlack = $100 ;   { catches overrun of one record (max 255 bytes) }

type
  Tbufferparts  = record
                   bufferstart : integer ;
                   bufferend   : integer ;
                 end;

  Tbufferpart   = array[1..maxbuf] of Tbufferparts ;

var
  { multipart buffering }
  buffer        : array[0 .. WindowSize + WindowSlack - 1] of byte ;
  bufferparts   : Tbufferpart ;
  buffers_inuse : integer ;  { buffers 1 .. buffers_inuse }
  currentbuf    : integer ;
  buffercnt     : integer ;
  loadfile,
  savefile      : file of byte ; { savefile reused for parts }
  SaveFilePath,
  SaveFileName,
  SaveFileExtension,
  FullSaveFileName : string ;   { multipart files get startaddress appended to name }

  LoadFileOpen : boolean ;
  SaveFileOpen : boolean ;
  hloaded,
  saved        : boolean ;
  exitreason   : string ;
  startaddress : integer ;
  endaddress   : integer ;
  tapeID       : byte ;

procedure Initbuffer(fillbyte : byte) ;
procedure SplitSaveFilename(const filename : string) ;

{ open loadfile read only; false and exitreason set on error }
function  OpenLoadFile(const filename : string) : boolean ;
{ close loadfile / savefile, only if open }
procedure CloseLoadFile ;
procedure CloseSaveFile ;
{ check buffers_inuse and every bufferpart:
  0 <= bufferstart <= bufferend <= $FFFF; false and exitreason set if not }
function  ValidateBufferparts : boolean ;
{ one part startaddr..endaddr, also sets startaddress and endaddress }
procedure SetSinglePart(startaddr, endaddr : integer) ;

implementation

procedure Initbuffer(fillbyte : byte) ;
var
  cnt : integer ;
begin
  FillChar(buffer, SizeOf(buffer), fillbyte) ;
  buffers_inuse := 0 ;
  currentbuf := 1 ;
  for cnt := 1 to maxbuf do
    begin
      bufferparts[cnt].bufferstart := 0 ;
      bufferparts[cnt].bufferend := 0 ;
    end ;
end ;

procedure SplitSaveFilename(const filename : string) ;
{ split filename: path, name without extension, extension }
begin
  SaveFilePath      := ExtractFilePath(filename) ;
  FullSaveFileName  := ExtractFileName(filename) ;
  SaveFileExtension := ExtractFileExt(filename) ;
  SaveFileName      := ChangeFileExt(FullSaveFileName, '') ;
end ;

function OpenLoadFile(const filename : string) : boolean ;
begin
  CloseLoadFile ;
  OpenLoadFile := false ;
  if not FileExists(filename)
    then
      begin
        exitreason := 'File not found: ' + filename ;
        exit ;
      end ;
  try
    AssignFile(loadfile, filename) ;
    FileMode := fmOpenRead or fmShareDenyWrite ;
    Reset(loadfile) ;
    LoadFileOpen := true ;
    OpenLoadFile := true ;
  except
    on E: EInOutError do
      exitreason := 'Error opening ' + filename + ': ' + E.Message ;
  end ;
  FileMode := fmOpenReadWrite ;
end ;

procedure CloseLoadFile ;
begin
  if LoadFileOpen
    then
      begin
        try
          CloseFile(loadfile) ;
        except
          on E: EInOutError do ;
        end ;
        LoadFileOpen := false ;
      end ;
end ;

procedure CloseSaveFile ;
begin
  if SaveFileOpen
    then
      begin
        try
          CloseFile(savefile) ;
        except
          on E: EInOutError do ;
        end ;
        SaveFileOpen := false ;
      end ;
end ;

function ValidateBufferparts : boolean ;
var
  cnt : integer ;
begin
  ValidateBufferparts := false ;
  if (buffers_inuse < 1) or (buffers_inuse > maxbuf)
    then
      begin
        exitreason := 'No data found in file' ;
        exit ;
      end ;
  for cnt := 1 to buffers_inuse do
    with bufferparts[cnt] do
      begin
        if bufferend < bufferstart
          then
            begin
              exitreason := 'No data found in file' ;
              exit ;
            end ;
        if (bufferstart < 0) or (bufferend > $FFFF)
          then
            begin
              exitreason := 'Data outside address range $0000-$FFFF' ;
              exit ;
            end ;
      end ;
  ValidateBufferparts := true ;
end ;

procedure SetSinglePart(startaddr, endaddr : integer) ;
begin
  bufferparts[1].bufferstart := startaddr ;
  bufferparts[1].bufferend   := endaddr ;
  buffers_inuse := 1 ;
  currentbuf    := 1 ;
  startaddress  := startaddr ;
  endaddress    := endaddr ;
end ;

end.
