unit editbuffer;

{
  BinHexEditor - the edit buffer

  Holds the data being edited (2K .. 1M), the "empty" byte, a map of
  changed bytes and the undo/redo history (10 deep).

  Every change goes through BeginChange/EndChange: BeginChange stores the
  old contents of the region that will change, EndChange stores the new
  contents. Undo/redo restore size and region. A region can be beyond the
  current size (growing the buffer), so one mechanism covers byte edits,
  fill, delete, insert, paste, import and resize.

  No GUI code, so the unit is also used by the console tests.

  MIT License, Copyright (c) 2026 Hans Otten
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  KB = 1024 ;
  NrBufferSizes = 10 ;
  BufferSizes : array[0 .. NrBufferSizes - 1] of integer =
    (2*KB, 4*KB, 8*KB, 16*KB, 32*KB, 64*KB, 128*KB, 256*KB, 512*KB, 1024*KB) ;
  DefaultBufferSize = 64*KB ;
  MaxBufferSize     = 1024*KB ;
  MaxUndo           = 10 ;

type
  TUndoStep = class
    Offset     : integer ;
    SizeBefore : integer ;
    SizeAfter  : integer ;
    Before     : TBytes ;   { old contents of region (within old size) }
    After      : TBytes ;   { new contents of region (within new size) }
    Name       : string ;
  end ;

  { TEditBuffer }

  TEditBuffer = class
  private
    FData      : TBytes ;
    FChanged   : TBytes ;   { 1 = byte changed since load/save }
    FEmpty     : byte ;
    FModified  : boolean ;
    FUndo,
    FRedo      : TList ;
    FPending   : TUndoStep ;  { between BeginChange and EndChange }
    FPendLen   : integer ;
    FOnChange  : TNotifyEvent ;
    function  GetByte(index : integer) : byte ;
    function  GetSize : integer ;
    procedure ClearList(list : TList) ;
    procedure SetSizeRaw(newsize : integer) ;
    procedure Changed ;
    procedure MarkChanges(step : TUndoStep) ;
    procedure ApplyStep(step : TUndoStep ; undoit : boolean) ;
  public
    constructor Create ;
    destructor Destroy ; override ;

    { new buffer of given size, all empty bytes; clears undo }
    procedure NewBuffer(asize : integer) ;
    { replace contents (load); size is rounded up to a buffer size,
      at least minsize; clears undo; false if > 1M }
    function  LoadData(const data : TBytes ; minsize : integer) : boolean ;
    procedure ClearUndo ;
    procedure ClearChangedMap ;

    { change region offset .. offset+len-1 (may extend beyond size) }
    procedure BeginChange(offset, len : integer ; const aname : string) ;
    procedure EndChange ;
    function  InChange : boolean ;

    { raw operations, use inside BeginChange/EndChange }
    procedure RawSetByte(offset : integer ; value : byte) ;
    procedure RawDelete(offset, count : integer) ;
    procedure RawInsert(offset, count : integer) ;
    procedure RawWrite(offset : integer ; const src ; count : integer) ;
    procedure RawResize(newsize : integer) ;

    { complete operations, each one undo step }
    procedure SetByte(offset : integer ; value : byte) ;
    procedure Fill(offset, count : integer ; value : byte) ;
    procedure Delete(offset, count : integer) ;
    procedure Write(offset : integer ; const src : TBytes) ;
    procedure Resize(newsize : integer) ;

    function  CanUndo : boolean ;
    function  CanRedo : boolean ;
    function  UndoName : string ;
    function  RedoName : string ;
    procedure Undo ;
    procedure Redo ;

    { true if all bytes offset .. offset+count-1 are the empty byte }
    function  IsEmptyRange(offset, count : integer) : boolean ;
    function  IsChanged(offset : integer) : boolean ;
    function  Copy(offset, count : integer) : TBytes ;
    function  DataPtr : PByte ;

    property Bytes[index : integer] : byte read GetByte ; default ;
    property Size : integer read GetSize ;
    property EmptyByte : byte read FEmpty write FEmpty ;
    property Modified : boolean read FModified write FModified ;
    property OnChange : TNotifyEvent read FOnChange write FOnChange ;
  end ;

{ smallest buffer size >= needed, -1 if > 1M }
function RoundUpBufferSize(needed : integer) : integer ;
function BufferSizeText(asize : integer) : string ;

implementation

function RoundUpBufferSize(needed : integer) : integer ;
var
  i : integer ;
begin
  for i := 0 to NrBufferSizes - 1 do
    if BufferSizes[i] >= needed
      then
        exit(BufferSizes[i]) ;
  Result := -1 ;
end ;

function BufferSizeText(asize : integer) : string ;
begin
  if (asize mod KB) = 0
    then
      Result := IntToStr(asize div KB) + 'K'
    else
      Result := IntToStr(asize) + ' bytes' ;
end ;

{ TEditBuffer }

constructor TEditBuffer.Create ;
begin
  inherited Create ;
  FUndo := TList.Create ;
  FRedo := TList.Create ;
  FEmpty := $FF ;
  NewBuffer(DefaultBufferSize) ;
end ;

destructor TEditBuffer.Destroy ;
begin
  ClearList(FUndo) ;
  ClearList(FRedo) ;
  FUndo.Free ;
  FRedo.Free ;
  FPending.Free ;
  inherited Destroy ;
end ;

procedure TEditBuffer.ClearList(list : TList) ;
var
  i : integer ;
begin
  for i := 0 to list.Count - 1 do
    TUndoStep(list[i]).Free ;
  list.Clear ;
end ;

function TEditBuffer.GetByte(index : integer) : byte ;
begin
  Result := FData[index] ;
end ;

function TEditBuffer.GetSize : integer ;
begin
  Result := Length(FData) ;
end ;

function TEditBuffer.DataPtr : PByte ;
begin
  if Length(FData) > 0
    then
      Result := @FData[0]
    else
      Result := nil ;
end ;

procedure TEditBuffer.Changed ;
begin
  if Assigned(FOnChange)
    then
      FOnChange(Self) ;
end ;

procedure TEditBuffer.SetSizeRaw(newsize : integer) ;
var
  oldsize : integer ;
begin
  oldsize := Length(FData) ;
  SetLength(FData, newsize) ;
  SetLength(FChanged, newsize) ;
  if newsize > oldsize
    then
      begin
        FillChar(FData[oldsize], newsize - oldsize, FEmpty) ;
        FillChar(FChanged[oldsize], newsize - oldsize, 0) ;
      end ;
end ;

procedure TEditBuffer.NewBuffer(asize : integer) ;
begin
  FPending.Free ;
  FPending := nil ;
  SetLength(FData, 0) ;
  SetLength(FChanged, 0) ;
  SetSizeRaw(asize) ;
  ClearUndo ;
  FModified := false ;
  Changed ;
end ;

function TEditBuffer.LoadData(const data : TBytes ; minsize : integer) : boolean ;
var
  newsize : integer ;
begin
  Result := false ;
  if Length(data) > minsize
    then
      newsize := RoundUpBufferSize(Length(data))
    else
      newsize := RoundUpBufferSize(minsize) ;
  if newsize < 0
    then
      exit ;
  NewBuffer(newsize) ;
  if Length(data) > 0
    then
      Move(data[0], FData[0], Length(data)) ;
  Result := true ;
  Changed ;
end ;

procedure TEditBuffer.ClearUndo ;
begin
  ClearList(FUndo) ;
  ClearList(FRedo) ;
end ;

procedure TEditBuffer.ClearChangedMap ;
begin
  if Length(FChanged) > 0
    then
      FillChar(FChanged[0], Length(FChanged), 0) ;
  Changed ;
end ;

procedure TEditBuffer.BeginChange(offset, len : integer ; const aname : string) ;
var
  n : integer ;
begin
  if FPending <> nil
    then
      EndChange ;
  if offset < 0
    then
      begin
        len := len + offset ;
        offset := 0 ;
      end ;
  if len < 0
    then
      len := 0 ;
  FPending := TUndoStep.Create ;
  FPending.Offset := offset ;
  FPending.Name := aname ;
  FPending.SizeBefore := Length(FData) ;
  FPendLen := len ;
  n := len ;
  if offset + n > Length(FData)
    then
      n := Length(FData) - offset ;
  if n < 0
    then
      n := 0 ;
  SetLength(FPending.Before, n) ;
  if n > 0
    then
      Move(FData[offset], FPending.Before[0], n) ;
end ;

procedure TEditBuffer.EndChange ;
var
  n : integer ;
  step : TUndoStep ;
begin
  if FPending = nil
    then
      exit ;
  step := FPending ;
  FPending := nil ;
  step.SizeAfter := Length(FData) ;
  n := FPendLen ;
  if step.Offset + n > Length(FData)
    then
      n := Length(FData) - step.Offset ;
  if n < 0
    then
      n := 0 ;
  SetLength(step.After, n) ;
  if n > 0
    then
      Move(FData[step.Offset], step.After[0], n) ;
  { nothing changed: no undo step }
  if (step.SizeBefore = step.SizeAfter) and
     (Length(step.Before) = Length(step.After)) and
     ((Length(step.Before) = 0) or
      CompareMem(@step.Before[0], @step.After[0], Length(step.Before)))
    then
      begin
        step.Free ;
        Changed ;
        exit ;
      end ;
  MarkChanges(step) ;
  FUndo.Add(step) ;
  while FUndo.Count > MaxUndo do
    begin
      TUndoStep(FUndo[0]).Free ;
      FUndo.Delete(0) ;
    end ;
  ClearList(FRedo) ;
  FModified := true ;
  Changed ;
end ;

function TEditBuffer.InChange : boolean ;
begin
  Result := FPending <> nil ;
end ;

procedure TEditBuffer.MarkChanges(step : TUndoStep) ;
var
  i, a : integer ;
  oldb : integer ;
begin
  for i := 0 to Length(step.After) - 1 do
    begin
      a := step.Offset + i ;
      if i < Length(step.Before)
        then
          oldb := step.Before[i]
        else
          oldb := FEmpty ;   { byte that was beyond the old size }
      if oldb <> step.After[i]
        then
          FChanged[a] := 1 ;
    end ;
end ;

procedure TEditBuffer.ApplyStep(step : TUndoStep ; undoit : boolean) ;
begin
  if undoit
    then
      begin
        SetSizeRaw(step.SizeBefore) ;
        if Length(step.Before) > 0
          then
            Move(step.Before[0], FData[step.Offset], Length(step.Before)) ;
      end
    else
      begin
        SetSizeRaw(step.SizeAfter) ;
        if Length(step.After) > 0
          then
            Move(step.After[0], FData[step.Offset], Length(step.After)) ;
      end ;
  FModified := true ;
end ;

procedure TEditBuffer.RawSetByte(offset : integer ; value : byte) ;
begin
  if (offset >= 0) and (offset < Length(FData))
    then
      FData[offset] := value ;
end ;

procedure TEditBuffer.RawDelete(offset, count : integer) ;
var
  sz : integer ;
begin
  sz := Length(FData) ;
  if (offset < 0) or (offset >= sz) or (count <= 0)
    then
      exit ;
  if offset + count > sz
    then
      count := sz - offset ;
  if offset + count < sz
    then
      Move(FData[offset + count], FData[offset], sz - offset - count) ;
  FillChar(FData[sz - count], count, FEmpty) ;
end ;

procedure TEditBuffer.RawInsert(offset, count : integer) ;
var
  sz : integer ;
begin
  sz := Length(FData) ;
  if (offset < 0) or (offset >= sz) or (count <= 0)
    then
      exit ;
  if offset + count > sz
    then
      count := sz - offset ;
  if offset + count < sz
    then
      Move(FData[offset], FData[offset + count], sz - offset - count) ;
  FillChar(FData[offset], count, FEmpty) ;
end ;

procedure TEditBuffer.RawWrite(offset : integer ; const src ; count : integer) ;
begin
  if (offset < 0) or (count <= 0)
    then
      exit ;
  if offset + count > Length(FData)
    then
      count := Length(FData) - offset ;
  if count > 0
    then
      Move(src, FData[offset], count) ;
end ;

procedure TEditBuffer.RawResize(newsize : integer) ;
begin
  SetSizeRaw(newsize) ;
end ;

procedure TEditBuffer.SetByte(offset : integer ; value : byte) ;
begin
  if (offset < 0) or (offset >= Length(FData))
    then
      exit ;
  if InChange
    then
      RawSetByte(offset, value)   { part of a running change (insert) }
    else
      begin
        BeginChange(offset, 1, 'Typing') ;
        RawSetByte(offset, value) ;
        EndChange ;
      end ;
end ;

procedure TEditBuffer.Fill(offset, count : integer ; value : byte) ;
begin
  if (offset < 0) or (count <= 0) or (offset >= Length(FData))
    then
      exit ;
  if offset + count > Length(FData)
    then
      count := Length(FData) - offset ;
  BeginChange(offset, count, 'Fill') ;
  FillChar(FData[offset], count, value) ;
  EndChange ;
end ;

procedure TEditBuffer.Delete(offset, count : integer) ;
begin
  if (offset < 0) or (count <= 0) or (offset >= Length(FData))
    then
      exit ;
  BeginChange(offset, Length(FData) - offset, 'Delete') ;
  RawDelete(offset, count) ;
  EndChange ;
end ;

procedure TEditBuffer.Write(offset : integer ; const src : TBytes) ;
begin
  if (offset < 0) or (Length(src) = 0) or (offset >= Length(FData))
    then
      exit ;
  BeginChange(offset, Length(src), 'Paste') ;
  RawWrite(offset, src[0], Length(src)) ;
  EndChange ;
end ;

procedure TEditBuffer.Resize(newsize : integer) ;
var
  oldsize : integer ;
begin
  oldsize := Length(FData) ;
  if newsize = oldsize
    then
      exit ;
  if newsize < oldsize
    then
      BeginChange(newsize, oldsize - newsize, 'Resize')
    else
      BeginChange(oldsize, newsize - oldsize, 'Resize') ;
  SetSizeRaw(newsize) ;
  EndChange ;
end ;

function TEditBuffer.CanUndo : boolean ;
begin
  Result := FUndo.Count > 0 ;
end ;

function TEditBuffer.CanRedo : boolean ;
begin
  Result := FRedo.Count > 0 ;
end ;

function TEditBuffer.UndoName : string ;
begin
  if CanUndo
    then
      Result := TUndoStep(FUndo[FUndo.Count - 1]).Name
    else
      Result := '' ;
end ;

function TEditBuffer.RedoName : string ;
begin
  if CanRedo
    then
      Result := TUndoStep(FRedo[FRedo.Count - 1]).Name
    else
      Result := '' ;
end ;

procedure TEditBuffer.Undo ;
var
  step : TUndoStep ;
begin
  EndChange ;
  if not CanUndo
    then
      exit ;
  step := TUndoStep(FUndo[FUndo.Count - 1]) ;
  FUndo.Delete(FUndo.Count - 1) ;
  ApplyStep(step, true) ;
  FRedo.Add(step) ;
  Changed ;
end ;

procedure TEditBuffer.Redo ;
var
  step : TUndoStep ;
begin
  EndChange ;
  if not CanRedo
    then
      exit ;
  step := TUndoStep(FRedo[FRedo.Count - 1]) ;
  FRedo.Delete(FRedo.Count - 1) ;
  ApplyStep(step, false) ;
  MarkChanges(step) ;
  FUndo.Add(step) ;
  Changed ;
end ;

function TEditBuffer.IsEmptyRange(offset, count : integer) : boolean ;
var
  i : integer ;
begin
  Result := true ;
  for i := offset to offset + count - 1 do
    if (i >= 0) and (i < Length(FData)) and (FData[i] <> FEmpty)
      then
        exit(false) ;
end ;

function TEditBuffer.IsChanged(offset : integer) : boolean ;
begin
  Result := (offset >= 0) and (offset < Length(FChanged)) and
            (FChanged[offset] <> 0) ;
end ;

function TEditBuffer.Copy(offset, count : integer) : TBytes ;
begin
  Result := nil ;
  if (offset < 0) or (offset >= Length(FData)) or (count <= 0)
    then
      exit ;
  if offset + count > Length(FData)
    then
      count := Length(FData) - offset ;
  SetLength(Result, count) ;
  Move(FData[offset], Result[0], count) ;
end ;

end.
