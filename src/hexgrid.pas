unit hexgrid;

{
  BinHexEditor - the hex/ASCII grid

  A TDrawGrid that draws straight from the edit buffer:

    col 0          address (base address + offset)
    col 1..N       hex bytes          (N = 16 or 32 bytes per row)
    col N+1        blank
    col N+2..2N+1  ASCII characters
    row 0          header

  Own cursor, selection, keyboard and mouse handling; the grid's own
  selection and editing are not used.

  MIT License, Copyright (c) 2026 Hans Otten
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Grids, LCLType, LCLIntf, Dialogs,
  StdCtrls,
  editbuffer;

type
  TPane = (paHex, paAscii) ;

  TGridColors = record
    Address   : TColor ;   { address column text }
    Hex       : TColor ;   { hex text }
    Ascii     : TColor ;   { ASCII text }
    Header    : TColor ;   { header and address background }
    Cursor    : TColor ;   { cursor background (text inverse) }
    Selection : TColor ;   { selection background }
    Modified  : TColor ;   { text of changed bytes }
  end ;

  { THexGrid }

  THexGrid = class(TDrawGrid)
  private
    FBuf          : TEditBuffer ;
    FPerRow       : integer ;
    FCurOfs       : integer ;
    FPane         : TPane ;
    FAnchor       : integer ;
    FSelActive    : boolean ;
    FHalfNibble   : boolean ;
    FNibble       : byte ;
    FInsertMode   : boolean ;
    FFreshCell    : boolean ;
    FInsertWarned : boolean ;
    FMouseSel     : boolean ;
    FBaseAddress  : integer ;
    FStripBit7    : boolean ;
    FColors       : TGridColors ;
    FCharW        : integer ;
    FAddrDigits   : integer ;
    FOnStatus     : TNotifyEvent ;
    procedure SetPerRow(value : integer) ;
    procedure SetBaseAddress(value : integer) ;
    procedure SetStripBit7(value : boolean) ;
    procedure SetColors(const value : TGridColors) ;
    function  OffsetToCol(offset : integer ; pane : TPane) : integer ;
    function  OffsetToRow(offset : integer) : integer ;
    function  CellToOffset(acol, arow : integer ; out pane : TPane) : integer ;
    procedure InvalidateOffset(offset : integer) ;
    procedure DoStatus ;
    procedure MoveCursor(newofs : integer ; extend : boolean) ;
    procedure EnsureVisible(offset : integer) ;
    procedure TypeHex(digit : integer) ;
    procedure TypeChar(c : byte) ;
    procedure StartInsert ;
    procedure AddInsertCell(at : integer) ;
    function  ConfirmLastByteLoss : boolean ;
    procedure DeleteAtCursor ;
  protected
    procedure DrawCell(aCol, aRow : integer ; aRect : TRect ;
                       aState : TGridDrawState) ; override ;
    procedure KeyDown(var Key : Word ; Shift : TShiftState) ; override ;
    procedure UTF8KeyPress(var UTF8Key : TUTF8Char) ; override ;
    procedure MouseDown(Button : TMouseButton ; Shift : TShiftState ;
                        X, Y : integer) ; override ;
    procedure MouseMove(Shift : TShiftState ; X, Y : integer) ; override ;
    procedure MouseUp(Button : TMouseButton ; Shift : TShiftState ;
                      X, Y : integer) ; override ;
  public
    constructor Create(AOwner : TComponent) ; override ;
    procedure SetBuffer(abuf : TEditBuffer) ;
    { recalculate sizes, rows and columns }
    procedure UpdateLayout ;
    { buffer changed from outside (undo, fill, import, resize ...) }
    procedure DataChanged ;
    { end insert mode and half entered byte, before other commands }
    procedure FinishEdit ;
    procedure GotoOffset(offset : integer) ;
    procedure SelectRange(first, last : integer) ;
    procedure SelectAll ;
    procedure ClearSelection ;
    function  HasSelection : boolean ;
    function  SelStart : integer ;
    function  SelEnd : integer ;
    { width needed to show all columns without horizontal scrolling }
    function  NeededWidth : integer ;
    { pixels missing to show all columns, 0 if all fit }
    function  ExtraWidthNeeded : integer ;
    { horizontal scrollbar only when the columns do not fit }
    procedure AdjustScrollBars ;

    property CursorOffset : integer read FCurOfs ;
    property ActivePane : TPane read FPane ;
    property InsertMode : boolean read FInsertMode ;
    property BytesPerRow : integer read FPerRow write SetPerRow ;
    property BaseAddress : integer read FBaseAddress write SetBaseAddress ;
    property StripBit7 : boolean read FStripBit7 write SetStripBit7 ;
    property Colors : TGridColors read FColors write SetColors ;
    property OnStatus : TNotifyEvent read FOnStatus write FOnStatus ;
  end ;

const
  DefaultColors : TGridColors = (
    Address   : clNavy ;
    Hex       : clBlack ;
    Ascii     : clMaroon ;
    Header    : $00E8E8E8 ;
    Cursor    : clNavy ;
    Selection : $00F0D8B0 ;   { light blue (BGR) }
    Modified  : clRed ) ;

{ character shown in the ASCII part }
function AsciiChar(b : byte ; stripbit7 : boolean) : char ;

implementation

function AsciiChar(b : byte ; stripbit7 : boolean) : char ;
begin
  if stripbit7 and (b >= $A0) and (b <= $FE)
    then
      b := b and $7F ;
  if (b >= $20) and (b <= $7E)
    then
      Result := chr(b)
    else
      Result := '.' ;
end ;

{ THexGrid }

constructor THexGrid.Create(AOwner : TComponent) ;
begin
  inherited Create(AOwner) ;
  FPerRow := 16 ;
  FColors := DefaultColors ;
  FAddrDigits := 5 ;
  Options := [goTabs, goThumbTracking] ;
  MouseWheelOption := mwGrid ;   { wheel scrolls, does not move cursor }
  GridLineWidth := 0 ;
  FocusRectVisible := false ;
  FixedCols := 1 ;
  FixedRows := 1 ;
  Flat := true ;
  BorderStyle := bsNone ;
  TabStop := true ;
  ScrollBars := ssAutoVertical ;
  {$IFDEF WINDOWS}
  Font.Name := 'Consolas' ;
  {$ELSE}
  {$IFDEF DARWIN}
  Font.Name := 'Menlo' ;
  {$ELSE}
  Font.Name := 'Monospace' ;
  {$ENDIF}
  {$ENDIF}
  Font.Size := 10 ;
end ;

procedure THexGrid.SetBuffer(abuf : TEditBuffer) ;
begin
  FBuf := abuf ;
  FCurOfs := 0 ;
  FAnchor := 0 ;
  FSelActive := false ;
  UpdateLayout ;
end ;

procedure THexGrid.UpdateLayout ;
var
  bmp   : TBitmap ;
  charh,
  i     : integer ;
  maxad : int64 ;
begin
  if FBuf = nil
    then
      exit ;
  bmp := TBitmap.Create ;
  try
    bmp.Canvas.Font.Assign(Font) ;
    FCharW := bmp.Canvas.TextWidth('0') ;
    charh := bmp.Canvas.TextHeight('0Ag') ;
  finally
    bmp.Free ;
  end ;
  if FCharW <= 0 then FCharW := 8 ;
  if charh <= 0 then charh := 14 ;
  maxad := int64(FBaseAddress) + FBuf.Size - 1 ;
  if maxad > $FFFFF
    then
      FAddrDigits := 6
    else
      FAddrDigits := 5 ;
  BeginUpdate ;
  try
    ColCount := 2 * FPerRow + 2 ;
    RowCount := 1 + (FBuf.Size + FPerRow - 1) div FPerRow ;
    DefaultRowHeight := charh + 4 ;
    ColWidths[0] := (FAddrDigits + 2) * FCharW ;
    for i := 1 to FPerRow do
      ColWidths[i] := 3 * FCharW ;
    ColWidths[FPerRow + 1] := 2 * FCharW ;
    for i := FPerRow + 2 to 2 * FPerRow + 1 do
      ColWidths[i] := FCharW + 1 ;
  finally
    EndUpdate ;
  end ;
  if FCurOfs >= FBuf.Size
    then
      FCurOfs := FBuf.Size - 1 ;
  if FAnchor >= FBuf.Size
    then
      FAnchor := FBuf.Size - 1 ;
  EnsureVisible(FCurOfs) ;
  Invalidate ;
  DoStatus ;
end ;

function THexGrid.NeededWidth : integer ;
var
  i : integer ;
begin
  Result := 0 ;
  for i := 0 to ColCount - 1 do
    Result := Result + ColWidths[i] ;
  Result := Result + 2 * FCharW + GetSystemMetrics(SM_CXVSCROLL) + 8 ;
end ;

function THexGrid.ExtraWidthNeeded : integer ;
begin
  Result := GridWidth - ClientWidth ;
  if Result > 0
    then
      Result := Result + 2
    else
      Result := 0 ;
end ;

procedure THexGrid.AdjustScrollBars ;
var
  sb : TScrollStyle ;
begin
  { compare with the full width: ClientWidth depends on the scrollbars }
  if GridWidth + GetSystemMetrics(SM_CXVSCROLL) + 4 > Width
    then
      sb := ssAutoBoth
    else
      sb := ssAutoVertical ;
  if ScrollBars <> sb
    then
      ScrollBars := sb ;
end ;

procedure THexGrid.SetPerRow(value : integer) ;
begin
  if (value <> 16) and (value <> 32)
    then
      value := 16 ;
  if value = FPerRow
    then
      exit ;
  FPerRow := value ;
  UpdateLayout ;
end ;

procedure THexGrid.SetBaseAddress(value : integer) ;
begin
  FBaseAddress := value ;
  UpdateLayout ;
end ;

procedure THexGrid.SetStripBit7(value : boolean) ;
begin
  FStripBit7 := value ;
  Invalidate ;
end ;

procedure THexGrid.SetColors(const value : TGridColors) ;
begin
  FColors := value ;
  Invalidate ;
end ;

function THexGrid.OffsetToCol(offset : integer ; pane : TPane) : integer ;
begin
  if pane = paHex
    then
      Result := 1 + offset mod FPerRow
    else
      Result := FPerRow + 2 + offset mod FPerRow ;
end ;

function THexGrid.OffsetToRow(offset : integer) : integer ;
begin
  Result := 1 + offset div FPerRow ;
end ;

function THexGrid.CellToOffset(acol, arow : integer ; out pane : TPane) : integer ;
var
  i : integer ;
begin
  Result := -1 ;
  pane := paHex ;
  if (arow < 1) or (FBuf = nil)
    then
      exit ;
  if (acol >= 1) and (acol <= FPerRow)
    then
      begin
        i := acol - 1 ;
        pane := paHex ;
      end
    else
      if (acol >= FPerRow + 2) and (acol <= 2 * FPerRow + 1)
        then
          begin
            i := acol - FPerRow - 2 ;
            pane := paAscii ;
          end
        else
          exit ;
  Result := (arow - 1) * FPerRow + i ;
  if Result >= FBuf.Size
    then
      Result := -1 ;
end ;

procedure THexGrid.InvalidateOffset(offset : integer) ;
begin
  if (FBuf = nil) or (offset < 0) or (offset >= FBuf.Size)
    then
      exit ;
  InvalidateCell(OffsetToCol(offset, paHex), OffsetToRow(offset)) ;
  InvalidateCell(OffsetToCol(offset, paAscii), OffsetToRow(offset)) ;
end ;

procedure THexGrid.DoStatus ;
begin
  if Assigned(FOnStatus)
    then
      FOnStatus(Self) ;
end ;

function THexGrid.HasSelection : boolean ;
begin
  Result := FSelActive ;
end ;

function THexGrid.SelStart : integer ;
begin
  if FSelActive
    then
      begin
        if FAnchor < FCurOfs
          then
            Result := FAnchor
          else
            Result := FCurOfs ;
      end
    else
      Result := FCurOfs ;
end ;

function THexGrid.SelEnd : integer ;
begin
  if FSelActive
    then
      begin
        if FAnchor > FCurOfs
          then
            Result := FAnchor
          else
            Result := FCurOfs ;
      end
    else
      Result := FCurOfs ;
end ;

procedure THexGrid.ClearSelection ;
begin
  if FSelActive
    then
      begin
        FSelActive := false ;
        Invalidate ;
      end ;
  FAnchor := FCurOfs ;
  DoStatus ;
end ;

procedure THexGrid.SelectRange(first, last : integer) ;
begin
  if FBuf = nil
    then
      exit ;
  FinishEdit ;
  if first < 0 then first := 0 ;
  if last >= FBuf.Size then last := FBuf.Size - 1 ;
  if last < first then last := first ;
  FAnchor := first ;
  FCurOfs := last ;
  FSelActive := last > first ;
  EnsureVisible(last) ;
  EnsureVisible(first) ;
  Invalidate ;
  DoStatus ;
end ;

procedure THexGrid.SelectAll ;
begin
  if FBuf <> nil
    then
      SelectRange(0, FBuf.Size - 1) ;
end ;

procedure THexGrid.EnsureVisible(offset : integer) ;
var
  r, vis : integer ;
begin
  if (FBuf = nil) or (offset < 0)
    then
      exit ;
  r := OffsetToRow(offset) ;
  vis := VisibleRowCount ;
  if vis < 1
    then
      vis := 1 ;
  if r < TopRow
    then
      TopRow := r
    else
      if r >= TopRow + vis
        then
          TopRow := r - vis + 1 ;
end ;

procedure THexGrid.GotoOffset(offset : integer) ;
begin
  FinishEdit ;
  FSelActive := false ;
  MoveCursor(offset, false) ;
  Invalidate ;
end ;

procedure THexGrid.MoveCursor(newofs : integer ; extend : boolean) ;
var
  old : integer ;
  hadsel : boolean ;
begin
  if FBuf = nil
    then
      exit ;
  if newofs < 0 then newofs := 0 ;
  if newofs >= FBuf.Size then newofs := FBuf.Size - 1 ;
  FHalfNibble := false ;
  old := FCurOfs ;
  hadsel := FSelActive ;
  if extend
    then
      begin
        if not FSelActive
          then
            FAnchor := FCurOfs ;
        FCurOfs := newofs ;
        FSelActive := FAnchor <> FCurOfs ;
      end
    else
      begin
        FCurOfs := newofs ;
        FAnchor := newofs ;
        FSelActive := false ;
      end ;
  EnsureVisible(FCurOfs) ;
  if hadsel or FSelActive
    then
      Invalidate
    else
      begin
        InvalidateOffset(old) ;
        InvalidateOffset(FCurOfs) ;
      end ;
  DoStatus ;
end ;

procedure THexGrid.DataChanged ;
begin
  FHalfNibble := false ;
  if FBuf = nil
    then
      exit ;
  if RowCount <> 1 + (FBuf.Size + FPerRow - 1) div FPerRow
    then
      UpdateLayout
    else
      begin
        if FCurOfs >= FBuf.Size then FCurOfs := FBuf.Size - 1 ;
        if FAnchor >= FBuf.Size then FAnchor := FBuf.Size - 1 ;
        Invalidate ;
        DoStatus ;
      end ;
end ;

procedure THexGrid.FinishEdit ;
begin
  if FHalfNibble
    then
      begin
        FHalfNibble := false ;
        InvalidateOffset(FCurOfs) ;
      end ;
  if FInsertMode
    then
      begin
        FInsertMode := false ;
        FBuf.EndChange ;
        Invalidate ;
        DoStatus ;
      end ;
end ;

{ drawing }

procedure THexGrid.DrawCell(aCol, aRow : integer ; aRect : TRect ;
                            aState : TGridDrawState) ;
var
  s      : string ;
  bg, fg : TColor ;
  ofs, i : integer ;
  pane   : TPane ;
  b      : byte ;
  frame  : boolean ;
  x      : integer ;
begin
  if FBuf = nil
    then
      exit ;
  Canvas.Font := Font ;
  frame := false ;
  s := '' ;
  bg := Color ;
  if bg = clDefault then bg := clWindow ;
  fg := FColors.Hex ;
  if aRow = 0
    then
      begin
        { header }
        bg := FColors.Header ;
        fg := FColors.Address ;
        if (aCol >= 1) and (aCol <= FPerRow)
          then
            begin
              i := aCol - 1 ;
              if FPerRow = 16
                then
                  s := IntToHex(i, 1)
                else
                  s := IntToHex(i, 2) ;
            end
          else
            if aCol >= FPerRow + 2
              then
                s := IntToHex((aCol - FPerRow - 2) mod 16, 1)
              else
                if aCol = 0
                  then
                    s := 'Addr' ;
      end
    else
      if aCol = 0
        then
          begin
            bg := FColors.Header ;
            fg := FColors.Address ;
            s := IntToHex(FBaseAddress + (aRow - 1) * FPerRow, FAddrDigits) ;
          end
        else
          begin
            ofs := CellToOffset(aCol, aRow, pane) ;
            if ofs >= 0
              then
                begin
                  b := FBuf[ofs] ;
                  if pane = paHex
                    then
                      begin
                        fg := FColors.Hex ;
                        if (ofs = FCurOfs) and FHalfNibble and (FPane = paHex)
                          then
                            s := IntToHex(FNibble, 1) + '_'
                          else
                            s := IntToHex(b, 2) ;
                      end
                    else
                      begin
                        fg := FColors.Ascii ;
                        s := AsciiChar(b, FStripBit7) ;
                      end ;
                  if FBuf.IsChanged(ofs)
                    then
                      fg := FColors.Modified ;
                  if FSelActive and (ofs >= SelStart) and (ofs <= SelEnd)
                    then
                      bg := FColors.Selection ;
                  if ofs = FCurOfs
                    then
                      begin
                        if pane = FPane
                          then
                            begin
                              fg := bg ;
                              bg := FColors.Cursor ;
                              if fg = FColors.Cursor then fg := clWhite ;
                            end
                          else
                            frame := true ;
                      end ;
                end ;
          end ;

  Canvas.Brush.Style := bsSolid ;
  Canvas.Brush.Color := bg ;
  Canvas.FillRect(aRect) ;
  if frame
    then
      begin
        Canvas.Pen.Color := FColors.Cursor ;
        Canvas.Brush.Style := bsClear ;
        Canvas.Rectangle(aRect.Left, aRect.Top + 1, aRect.Right - 1,
                         aRect.Bottom - 1) ;
      end ;
  if s <> ''
    then
      begin
        Canvas.Brush.Style := bsClear ;
        Canvas.Font.Color := fg ;
        if (aCol >= 1) and (aCol <= FPerRow)
          then
            x := aRect.Left + (aRect.Right - aRect.Left -
                 Canvas.TextWidth(s)) div 2
          else
            if aCol = 0
              then
                x := aRect.Left + FCharW
              else
                x := aRect.Left + (aRect.Right - aRect.Left -
                     Canvas.TextWidth(s)) div 2 ;
        Canvas.TextOut(x, aRect.Top + 2, s) ;
      end ;
end ;

{ editing }

function THexGrid.ConfirmLastByteLoss : boolean ;
begin
  Result := true ;
  if FInsertWarned or FBuf.IsEmptyRange(FBuf.Size - 1, 1)
    then
      exit ;
  Result := MessageDlg('Insert',
              'The last byte of the buffer is not empty and falls off ' +
              'when a byte is inserted.' + LineEnding + 'Insert anyway?',
              mtConfirmation, [mbYes, mbNo], 0) = mrYes ;
  if Result
    then
      FInsertWarned := true ;
end ;

procedure THexGrid.StartInsert ;
begin
  FHalfNibble := false ;
  FInsertWarned := false ;
  FSelActive := false ;
  if not ConfirmLastByteLoss
    then
      exit ;
  FBuf.BeginChange(FCurOfs, FBuf.Size - FCurOfs, 'Insert') ;
  FBuf.RawInsert(FCurOfs, 1) ;
  FInsertMode := true ;
  FFreshCell := true ;
  Invalidate ;
  DoStatus ;
end ;

procedure THexGrid.AddInsertCell(at : integer) ;
begin
  if at >= FBuf.Size
    then
      begin
        Beep ;
        exit ;
      end ;
  if not ConfirmLastByteLoss
    then
      exit ;
  FBuf.RawInsert(at, 1) ;
  Invalidate ;
end ;

procedure THexGrid.TypeHex(digit : integer) ;
var
  value : byte ;
begin
  if FSelActive
    then
      ClearSelection ;
  if not FHalfNibble
    then
      begin
        FNibble := digit ;
        FHalfNibble := true ;
        InvalidateOffset(FCurOfs) ;
        exit ;
      end ;
  FHalfNibble := false ;
  value := FNibble * 16 + digit ;
  FBuf.SetByte(FCurOfs, value) ;   { inside insert change when inserting }
  if FInsertMode
    then
      begin
        FFreshCell := false ;
        InvalidateOffset(FCurOfs) ;   { stays on the inserted cell }
        DoStatus ;
      end
    else
      begin
        InvalidateOffset(FCurOfs) ;
        if FCurOfs < FBuf.Size - 1
          then
            MoveCursor(FCurOfs + 1, false)
          else
            DoStatus ;
      end ;
end ;

procedure THexGrid.TypeChar(c : byte) ;
begin
  if FSelActive
    then
      ClearSelection ;
  FHalfNibble := false ;
  if FInsertMode
    then
      begin
        if not FFreshCell
          then
            begin
              if not ConfirmLastByteLoss
                then
                  exit ;
              FBuf.RawInsert(FCurOfs, 1) ;
            end ;
        FBuf.RawSetByte(FCurOfs, c) ;
        FFreshCell := false ;
        if FCurOfs < FBuf.Size - 1
          then
            inc(FCurOfs) ;
        FAnchor := FCurOfs ;
        EnsureVisible(FCurOfs) ;
        Invalidate ;
        DoStatus ;
      end
    else
      begin
        FBuf.SetByte(FCurOfs, c) ;
        InvalidateOffset(FCurOfs) ;
        if FCurOfs < FBuf.Size - 1
          then
            MoveCursor(FCurOfs + 1, false)
          else
            DoStatus ;
      end ;
end ;

procedure THexGrid.DeleteAtCursor ;
var
  first, count : integer ;
begin
  FinishEdit ;
  first := SelStart ;
  count := SelEnd - SelStart + 1 ;
  FBuf.Delete(first, count) ;
  FSelActive := false ;
  FCurOfs := first ;
  FAnchor := first ;
  Invalidate ;
  DoStatus ;
end ;

procedure THexGrid.KeyDown(var Key : Word ; Shift : TShiftState) ;
var
  ext   : boolean ;
  page  : integer ;
  ctrl  : boolean ;
begin
  if FBuf = nil
    then
      begin
        inherited KeyDown(Key, Shift) ;
        exit ;
      end ;
  ext := ssShift in Shift ;
  ctrl := ssCtrl in Shift ;
  page := VisibleRowCount - 1 ;
  if page < 1 then page := 1 ;
  case Key of
    VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_HOME, VK_END, VK_PRIOR, VK_NEXT :
      begin
        FinishEdit ;
        case Key of
          VK_LEFT  : MoveCursor(FCurOfs - 1, ext) ;
          VK_RIGHT : MoveCursor(FCurOfs + 1, ext) ;
          VK_UP    : if FCurOfs >= FPerRow
                       then MoveCursor(FCurOfs - FPerRow, ext) ;
          VK_DOWN  : if FCurOfs + FPerRow < FBuf.Size
                       then MoveCursor(FCurOfs + FPerRow, ext) ;
          VK_HOME  : if ctrl
                       then MoveCursor(0, ext)
                       else MoveCursor(FCurOfs - FCurOfs mod FPerRow, ext) ;
          VK_END   : if ctrl
                       then MoveCursor(FBuf.Size - 1, ext)
                       else MoveCursor(FCurOfs - FCurOfs mod FPerRow +
                                       FPerRow - 1, ext) ;
          VK_PRIOR : begin
                       if FCurOfs - page * FPerRow >= 0
                         then MoveCursor(FCurOfs - page * FPerRow, ext)
                         else MoveCursor(FCurOfs mod FPerRow, ext) ;
                       TopRow := TopRow - page ;
                     end ;
          VK_NEXT  : begin
                       if FCurOfs + page * FPerRow < FBuf.Size
                         then MoveCursor(FCurOfs + page * FPerRow, ext)
                         else MoveCursor(FBuf.Size - 1, ext) ;
                       TopRow := TopRow + page ;
                       EnsureVisible(FCurOfs) ;
                     end ;
        end ;
        Key := 0 ;
      end ;
    VK_TAB :
      begin
        if FInsertMode
          then
            begin
              AddInsertCell(FCurOfs + 1) ;
              if FCurOfs < FBuf.Size - 1
                then
                  begin
                    inc(FCurOfs) ;
                    FAnchor := FCurOfs ;
                    FFreshCell := true ;
                    FHalfNibble := false ;
                    EnsureVisible(FCurOfs) ;
                    Invalidate ;
                    DoStatus ;
                  end ;
            end
          else
            begin
              FHalfNibble := false ;
              if FPane = paHex then FPane := paAscii else FPane := paHex ;
              Invalidate ;
              DoStatus ;
            end ;
        Key := 0 ;
      end ;
    VK_INSERT :
      begin
        if FInsertMode
          then
            begin
              { another cell, same as Tab }
              Key := VK_TAB ;
              KeyDown(Key, []) ;
            end
          else
            if not (ctrl or ext)    { Ctrl+Ins / Shift+Ins: clipboard }
              then
                StartInsert ;
        Key := 0 ;
      end ;
    VK_DELETE :
      begin
        if not (ext or ctrl)
          then
            DeleteAtCursor ;
        Key := 0 ;
      end ;
    VK_RETURN :
      begin
        FinishEdit ;
        Key := 0 ;
      end ;
    VK_ESCAPE :
      begin
        if FHalfNibble or FInsertMode
          then
            FinishEdit
          else
            ClearSelection ;
        Key := 0 ;
      end ;
    VK_BACK :
      begin
        if FHalfNibble
          then
            begin
              FHalfNibble := false ;
              InvalidateOffset(FCurOfs) ;
            end
          else
            begin
              FinishEdit ;
              MoveCursor(FCurOfs - 1, false) ;
            end ;
        Key := 0 ;
      end ;
  else
    inherited KeyDown(Key, Shift) ;
  end ;
end ;

procedure THexGrid.UTF8KeyPress(var UTF8Key : TUTF8Char) ;
var
  c : char ;
  v : integer ;
begin
  if (FBuf = nil) or (Length(UTF8Key) <> 1)
    then
      begin
        inherited UTF8KeyPress(UTF8Key) ;
        exit ;
      end ;
  c := UTF8Key[1] ;
  if c < ' '
    then
      begin
        UTF8Key := '' ;   { control characters handled in KeyDown }
        exit ;
      end ;
  if FPane = paHex
    then
      begin
        case c of
          '0'..'9' : v := ord(c) - ord('0') ;
          'A'..'F' : v := ord(c) - ord('A') + 10 ;
          'a'..'f' : v := ord(c) - ord('a') + 10 ;
        else
          v := -1 ;
        end ;
        if v >= 0
          then
            TypeHex(v)
          else
            Beep ;
      end
    else
      if c <= #126
        then
          TypeChar(ord(c)) ;
  UTF8Key := '' ;
end ;

{ mouse }

procedure THexGrid.MouseDown(Button : TMouseButton ; Shift : TShiftState ;
                             X, Y : integer) ;
var
  acol, arow : longint ;
  ofs : integer ;
  pane : TPane ;
begin
  if not Focused and CanFocus
    then
      SetFocus ;
  if FBuf = nil
    then
      exit ;
  MouseToCell(X, Y, acol, arow) ;
  ofs := CellToOffset(acol, arow, pane) ;
  if ofs < 0
    then
      exit ;
  FinishEdit ;
  if Button = mbLeft
    then
      begin
        FPane := pane ;
        if ssShift in Shift
          then
            MoveCursor(ofs, true)
          else
            begin
              MoveCursor(ofs, false) ;
              FMouseSel := true ;
            end ;
        Invalidate ;
      end
    else
      if Button = mbRight
        then
          begin
            { right click outside the selection moves the cursor }
            if not (FSelActive and (ofs >= SelStart) and (ofs <= SelEnd))
              then
                begin
                  FPane := pane ;
                  MoveCursor(ofs, false) ;
                  Invalidate ;
                end ;
          end ;
end ;

procedure THexGrid.MouseMove(Shift : TShiftState ; X, Y : integer) ;
var
  acol, arow : longint ;
  ofs : integer ;
  pane : TPane ;
begin
  if not FMouseSel or not (ssLeft in Shift) or (FBuf = nil)
    then
      exit ;
  { scroll when dragging above or below the grid }
  if (Y < RowHeights[0]) and (TopRow > 1)
    then
      begin
        TopRow := TopRow - 1 ;
        Y := RowHeights[0] + 1 ;
      end
    else
      if (Y >= ClientHeight) and (TopRow + VisibleRowCount < RowCount)
        then
          begin
            TopRow := TopRow + 1 ;
            Y := ClientHeight - 2 ;
          end ;
  MouseToCell(X, Y, acol, arow) ;
  ofs := CellToOffset(acol, arow, pane) ;
  if (ofs >= 0) and (ofs <> FCurOfs)
    then
      MoveCursor(ofs, true) ;
end ;

procedure THexGrid.MouseUp(Button : TMouseButton ; Shift : TShiftState ;
                           X, Y : integer) ;
begin
  FMouseSel := false ;
end ;

end.
