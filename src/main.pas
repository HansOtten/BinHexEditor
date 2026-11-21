unit main;

{
  BinHexEditor - main form: menus, status bar, commands

  MIT License, Copyright (c) 2026 Hans Otten
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  StdCtrls, Clipbrd, LCLType,
  editbuffer, hexgrid, importexport, searching, settings;

const
  AppName    = 'BinHexEditor' ;
  AppVersion = 'BinHexEditor V0.1 (November 2026)' ;
  AppAuthor  = 'Hans Otten, retro.hansotten.nl' ;
  MinClientWidth = 760 ;

type

  { TMainForm }

  TMainForm = class(TForm)
    ColorDialog1: TColorDialog;
    MainMenu1: TMainMenu;
    miAbout: TMenuItem;
    miBaseAddress: TMenuItem;
    miBuffer: TMenuItem;
    miChecksum: TMenuItem;
    miColors: TMenuItem;
    miCopy: TMenuItem;
    miEdit: TMenuItem;
    miEmptyByte: TMenuItem;
    miExit: TMenuItem;
    miExport: TMenuItem;
    miFile: TMenuItem;
    miFill: TMenuItem;
    miFind: TMenuItem;
    miFindNext: TMenuItem;
    miFindPrev: TMenuItem;
    miFontSize: TMenuItem;
    miGoto: TMenuItem;
    miHelp: TMenuItem;
    miHelpItem: TMenuItem;
    miImport: TMenuItem;
    miLoadBin: TMenuItem;
    miNew: TMenuItem;
    miOptions: TMenuItem;
    miPaste: TMenuItem;
    miPerRow16: TMenuItem;
    miPerRow32: TMenuItem;
    miRedo: TMenuItem;
    miSaveBin: TMenuItem;
    miSaveBinAs: TMenuItem;
    miSelectAll: TMenuItem;
    miSep1: TMenuItem;
    miSep2: TMenuItem;
    miSep3: TMenuItem;
    miSep4: TMenuItem;
    miSep5: TMenuItem;
    miSep6: TMenuItem;
    miSep7: TMenuItem;
    miStripBit7: TMenuItem;
    miUndo: TMenuItem;
    OpenDialog1: TOpenDialog;
    pmChecksum: TMenuItem;
    pmCopy: TMenuItem;
    pmExport: TMenuItem;
    pmFill: TMenuItem;
    pmImport: TMenuItem;
    pmPaste: TMenuItem;
    pmSep1: TMenuItem;
    pmSep2: TMenuItem;
    PopupMenu1: TPopupMenu;
    SaveDialog1: TSaveDialog;
    StatusBar1: TStatusBar;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure FormResize(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure miAboutClick(Sender: TObject);
    procedure miBaseAddressClick(Sender: TObject);
    procedure miChecksumClick(Sender: TObject);
    procedure miCopyClick(Sender: TObject);
    procedure miEditClick(Sender: TObject);
    procedure miEmptyByteClick(Sender: TObject);
    procedure miExitClick(Sender: TObject);
    procedure miExportClick(Sender: TObject);
    procedure miFillClick(Sender: TObject);
    procedure miFindClick(Sender: TObject);
    procedure miFindNextClick(Sender: TObject);
    procedure miFindPrevClick(Sender: TObject);
    procedure miGotoClick(Sender: TObject);
    procedure miHelpItemClick(Sender: TObject);
    procedure miImportClick(Sender: TObject);
    procedure miLoadBinClick(Sender: TObject);
    procedure miNewClick(Sender: TObject);
    procedure miPasteClick(Sender: TObject);
    procedure miPerRowClick(Sender: TObject);
    procedure miRedoClick(Sender: TObject);
    procedure miSaveBinAsClick(Sender: TObject);
    procedure miSaveBinClick(Sender: TObject);
    procedure miSelectAllClick(Sender: TObject);
    procedure miStripBit7Click(Sender: TObject);
    procedure miUndoClick(Sender: TObject);
    procedure pmImportClick(Sender: TObject);
    procedure PopupMenu1Popup(Sender: TObject);
  private
    FBuf      : TEditBuffer ;
    FGrid     : THexGrid ;
    FSettings : TAppSettings ;
    FFileName : string ;
    FSearch   : TSearchSpec ;
    FMessage  : string ;
    FShown    : boolean ;
    procedure BuildOptionMenus ;
    procedure SizeItemClick(Sender : TObject) ;
    procedure ColorItemClick(Sender : TObject) ;
    procedure DefaultColorsClick(Sender : TObject) ;
    procedure FontSizeClick(Sender : TObject) ;
    procedure UpdateMenus ;
    procedure GridStatus(Sender : TObject) ;
    procedure BufferChanged(Sender : TObject) ;
    procedure UpdateTitle ;
    procedure ShowMessageText(const s : string) ;
    procedure FitWidth ;
    function  CheckSave : boolean ;
    procedure LoadBin(const fn : string) ;
    function  SaveBin(const fn : string) : boolean ;
    procedure DoImport(atcursor : boolean) ;
    procedure DoSearch(backward : boolean ; from : integer) ;
    function  AskHex(const acaption, aprompt : string ; var value : integer ;
                     maxvalue : integer) : boolean ;
    function  OffsetText(ofs : integer) : string ;
  public
  end;

var
  MainForm: TMainForm;

implementation

uses
  importdlg, exportdlg, finddlg;

{$R *.lfm}

const
  ColorItemNames : array[0..6] of string =
    ('Address', 'Hex data', 'ASCII data', 'Header', 'Cursor', 'Selection',
     'Modified bytes') ;

function ColorOf(const c : TGridColors ; index : integer) : TColor ;
begin
  case index of
    0 : Result := c.Address ;
    1 : Result := c.Hex ;
    2 : Result := c.Ascii ;
    3 : Result := c.Header ;
    4 : Result := c.Cursor ;
    5 : Result := c.Selection ;
  else
    Result := c.Modified ;
  end ;
end ;

procedure SetColorOf(var c : TGridColors ; index : integer ; value : TColor) ;
begin
  case index of
    0 : c.Address := value ;
    1 : c.Hex := value ;
    2 : c.Ascii := value ;
    3 : c.Header := value ;
    4 : c.Cursor := value ;
    5 : c.Selection := value ;
  else
    c.Modified := value ;
  end ;
end ;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FSettings := TAppSettings.Create ;
  FSettings.Load ;

  FBuf := TEditBuffer.Create ;
  FBuf.EmptyByte := FSettings.EmptyByte ;
  FBuf.NewBuffer(FSettings.BufferSize) ;
  FBuf.OnChange := @BufferChanged ;

  FGrid := THexGrid.Create(Self) ;
  FGrid.Parent := Self ;
  FGrid.Align := alClient ;
  FGrid.PopupMenu := PopupMenu1 ;
  FGrid.Font.Size := FSettings.FontSize ;
  FGrid.Colors := FSettings.Colors ;
  FGrid.StripBit7 := FSettings.StripBit7 ;
  FGrid.BytesPerRow := FSettings.BytesPerRow ;
  FGrid.BaseAddress := FSettings.BaseAddress ;
  FGrid.OnStatus := @GridStatus ;
  FGrid.SetBuffer(FBuf) ;

  FSearch := Default(TSearchSpec) ;
  FSearch.Kind := FSettings.SearchKind ;
  FSearch.CaseSensitive := FSettings.SearchCase ;
  FSearch.IgnoreBit7 := FSettings.SearchBit7 ;
  FSearch.Wrap := FSettings.SearchWrap ;

  AllowDropFiles := true ;
  BuildOptionMenus ;
  UpdateMenus ;
  UpdateTitle ;
  if FSettings.WindowHeight > 200
    then
      Height := FSettings.WindowHeight ;
  FitWidth ;
  ActiveControl := FGrid ;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  if FShown
    then
      exit ;
  FShown := true ;
  FGrid.UpdateLayout ;
  FitWidth ;
  { file name on the command line: load as BIN }
  if (ParamCount > 0) and FileExists(ParamStr(1))
    then
      LoadBin(ParamStr(1)) ;
end;

procedure TMainForm.FormResize(Sender: TObject);
var
  i, w : integer ;
begin
  { last status panel (messages) gets the remaining width }
  w := ClientWidth ;
  for i := 0 to StatusBar1.Panels.Count - 2 do
    w := w - StatusBar1.Panels[i].Width ;
  if w < 50
    then
      w := 50 ;
  StatusBar1.Panels[StatusBar1.Panels.Count - 1].Width := w ;
  if FGrid <> nil
    then
      FGrid.AdjustScrollBars ;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FSettings.BufferSize := FBuf.Size ;
  FSettings.EmptyByte := FBuf.EmptyByte ;
  FSettings.BytesPerRow := FGrid.BytesPerRow ;
  FSettings.BaseAddress := FGrid.BaseAddress ;
  FSettings.StripBit7 := FGrid.StripBit7 ;
  FSettings.Colors := FGrid.Colors ;
  FSettings.FontSize := FGrid.Font.Size ;
  FSettings.SearchKind := FSearch.Kind ;
  FSettings.SearchCase := FSearch.CaseSensitive ;
  FSettings.SearchBit7 := FSearch.IgnoreBit7 ;
  FSettings.SearchWrap := FSearch.Wrap ;
  FSettings.WindowWidth := Width ;
  FSettings.WindowHeight := Height ;
  FSettings.Save ;
  FBuf.OnChange := nil ;
  FGrid.OnStatus := nil ;
  FSettings.Free ;
  FBuf.Free ;
end;

procedure TMainForm.FitWidth ;
var
  w : integer ;
begin
  w := FGrid.NeededWidth ;
  if w < MinClientWidth
    then
      w := MinClientWidth ;    { room for the status bar }
  if w > Screen.WorkAreaWidth
    then
      w := Screen.WorkAreaWidth ;
  ClientWidth := w ;
  { grid client width is known now: correct for the real scrollbar width }
  w := FGrid.ExtraWidthNeeded ;
  if (w > 0) and (ClientWidth + w <= Screen.WorkAreaWidth)
    then
      ClientWidth := ClientWidth + w ;
  FGrid.AdjustScrollBars ;
  if Left + Width > Screen.WorkAreaWidth
    then
      Left := 0 ;
end ;

{ menus }

procedure TMainForm.BuildOptionMenus ;
var
  i : integer ;
  mi : TMenuItem ;
begin
  miBuffer.Clear ;
  for i := 0 to NrBufferSizes - 1 do
    begin
      mi := TMenuItem.Create(Self) ;
      mi.Caption := BufferSizeText(BufferSizes[i]) ;
      if BufferSizes[i] = 64*KB
        then
          mi.Caption := mi.Caption + ' (default)' ;
      mi.Tag := BufferSizes[i] ;
      mi.RadioItem := true ;
      mi.GroupIndex := 2 ;
      mi.OnClick := @SizeItemClick ;
      miBuffer.Add(mi) ;
    end ;
  miColors.Clear ;
  for i := 0 to High(ColorItemNames) do
    begin
      mi := TMenuItem.Create(Self) ;
      mi.Caption := ColorItemNames[i] + '...' ;
      mi.Tag := i ;
      mi.OnClick := @ColorItemClick ;
      miColors.Add(mi) ;
    end ;
  mi := TMenuItem.Create(Self) ;
  mi.Caption := '-' ;
  miColors.Add(mi) ;
  mi := TMenuItem.Create(Self) ;
  mi.Caption := 'Default colors' ;
  mi.OnClick := @DefaultColorsClick ;
  miColors.Add(mi) ;
  miFontSize.Clear ;
  for i := 8 to 14 do
    begin
      mi := TMenuItem.Create(Self) ;
      mi.Caption := IntToStr(i) ;
      mi.Tag := i ;
      mi.RadioItem := true ;
      mi.GroupIndex := 3 ;
      mi.OnClick := @FontSizeClick ;
      miFontSize.Add(mi) ;
    end ;
end ;

procedure TMainForm.UpdateMenus ;
var
  i : integer ;
begin
  for i := 0 to miBuffer.Count - 1 do
    miBuffer.Items[i].Checked := miBuffer.Items[i].Tag = FBuf.Size ;
  for i := 0 to miFontSize.Count - 1 do
    miFontSize.Items[i].Checked := miFontSize.Items[i].Tag = FGrid.Font.Size ;
  miPerRow16.Checked := FGrid.BytesPerRow = 16 ;
  miPerRow32.Checked := FGrid.BytesPerRow = 32 ;
  miStripBit7.Checked := FGrid.StripBit7 ;
  miEmptyByte.Caption := Format('Empty byte ($%.2X)...', [FBuf.EmptyByte]) ;
  miBaseAddress.Caption := Format('Base address ($%X)...', [FGrid.BaseAddress]) ;
end ;

procedure TMainForm.miEditClick(Sender: TObject);
begin
  miUndo.Enabled := FBuf.CanUndo or FGrid.InsertMode ;
  if FBuf.CanUndo
    then
      miUndo.Caption := 'Undo ' + FBuf.UndoName
    else
      miUndo.Caption := 'Undo' ;
  miRedo.Enabled := FBuf.CanRedo ;
  if FBuf.CanRedo
    then
      miRedo.Caption := 'Redo ' + FBuf.RedoName
    else
      miRedo.Caption := 'Redo' ;
  miFill.Enabled := FGrid.HasSelection ;
  miFindNext.Enabled := Length(FSearch.Pattern) > 0 ;
  miFindPrev.Enabled := miFindNext.Enabled ;
end;

procedure TMainForm.PopupMenu1Popup(Sender: TObject);
begin
  FGrid.FinishEdit ;
  pmFill.Enabled := FGrid.HasSelection ;
  pmExport.Enabled := FGrid.HasSelection ;
end;

{ status }

function TMainForm.OffsetText(ofs : integer) : string ;
begin
  Result := IntToHex(ofs, 5) ;
  if FGrid.BaseAddress <> 0
    then
      Result := Result + ' ($' + IntToHex(FGrid.BaseAddress + ofs, 4) + ')' ;
end ;

procedure TMainForm.GridStatus(Sender : TObject) ;
var
  s : string ;
  b : byte ;
  ofs : integer ;
  c : char ;
begin
  ofs := FGrid.CursorOffset ;
  if (ofs >= 0) and (ofs < FBuf.Size)
    then
      begin
        b := FBuf[ofs] ;
        c := AsciiChar(b, FGrid.StripBit7) ;
        StatusBar1.Panels[0].Text := 'Offset ' + OffsetText(ofs) ;
        StatusBar1.Panels[1].Text := Format('$%.2X %3d ''%s''', [b, b, c]) ;
      end ;
  StatusBar1.Panels[2].Text := 'Size ' + BufferSizeText(FBuf.Size) ;
  if FGrid.InsertMode
    then
      StatusBar1.Panels[3].Text := 'INS'
    else
      StatusBar1.Panels[3].Text := 'OVR' ;
  if FBuf.Modified
    then
      StatusBar1.Panels[4].Text := 'Modified'
    else
      StatusBar1.Panels[4].Text := '' ;
  { selection and last message share the last (stretching) panel }
  if FGrid.HasSelection
    then
      s := Format('Sel %.5X-%.5X (%d)',
             [FGrid.SelStart, FGrid.SelEnd, FGrid.SelEnd - FGrid.SelStart + 1])
    else
      s := '' ;
  if FMessage <> ''
    then
      if s = ''
        then
          s := FMessage
        else
          s := s + '   ' + FMessage ;
  StatusBar1.Panels[5].Text := s ;
end ;

procedure TMainForm.ShowMessageText(const s : string) ;
begin
  FMessage := s ;
  GridStatus(nil) ;
end ;

procedure TMainForm.BufferChanged(Sender : TObject) ;
begin
  UpdateTitle ;
  GridStatus(nil) ;
end ;

procedure TMainForm.UpdateTitle ;
var
  s : string ;
begin
  if FFileName = ''
    then
      s := AppName + ' - (new)'
    else
      s := AppName + ' - ' + FFileName ;
  if FBuf.Modified
    then
      s := s + ' *' ;
  Caption := s ;
end ;

{ files }

function TMainForm.CheckSave : boolean ;
begin
  FGrid.FinishEdit ;
  Result := true ;
  if not FBuf.Modified
    then
      exit ;
  case MessageDlg(AppName, 'The buffer has unsaved changes. Save first?',
                  mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes : if FFileName <> ''
              then
                Result := SaveBin(FFileName)
              else
                begin
                  SaveDialog1.FileName := '' ;
                  SaveDialog1.InitialDir := FSettings.LastDir ;
                  Result := SaveDialog1.Execute and
                            SaveBin(SaveDialog1.FileName) ;
                end ;
    mrNo  : Result := true ;
  else
    Result := false ;
  end ;
end ;

procedure TMainForm.LoadBin(const fn : string) ;
var
  data : TBytes ;
  msg  : string ;
  oldsize : integer ;
begin
  if not ReadBinFile(fn, data, msg)
    then
      begin
        MessageDlg(AppName, msg, mtError, [mbOK], 0) ;
        exit ;
      end ;
  oldsize := FBuf.Size ;
  if not FBuf.LoadData(data, FBuf.Size)
    then
      begin
        MessageDlg(AppName, 'File is bigger than 1M', mtError, [mbOK], 0) ;
        exit ;
      end ;
  FFileName := fn ;
  FSettings.LastDir := ExtractFilePath(fn) ;
  FGrid.UpdateLayout ;
  FGrid.GotoOffset(0) ;
  UpdateMenus ;
  UpdateTitle ;
  msg := Format('Loaded %s (%d bytes)', [ExtractFileName(fn), Length(data)]) ;
  if FBuf.Size > oldsize
    then
      msg := msg + ', buffer size now ' + BufferSizeText(FBuf.Size) ;
  ShowMessageText(msg) ;
end ;

function TMainForm.SaveBin(const fn : string) : boolean ;
var
  msg : string ;
begin
  FGrid.FinishEdit ;
  Result := WriteBinFile(fn, FBuf.DataPtr^, FBuf.Size, msg) ;
  if not Result
    then
      begin
        MessageDlg(AppName, msg, mtError, [mbOK], 0) ;
        exit ;
      end ;
  FFileName := fn ;
  FSettings.LastDir := ExtractFilePath(fn) ;
  FBuf.Modified := false ;
  FBuf.ClearChangedMap ;
  FGrid.Invalidate ;
  UpdateTitle ;
  ShowMessageText(Format('Saved %s (%d bytes)', [ExtractFileName(fn), FBuf.Size])) ;
end ;

procedure TMainForm.miNewClick(Sender: TObject);
begin
  if not CheckSave
    then
      exit ;
  FBuf.NewBuffer(FBuf.Size) ;
  FFileName := '' ;
  FGrid.DataChanged ;
  FGrid.GotoOffset(0) ;
  UpdateTitle ;
  ShowMessageText('New buffer') ;
end;

procedure TMainForm.miLoadBinClick(Sender: TObject);
begin
  if not CheckSave
    then
      exit ;
  OpenDialog1.InitialDir := FSettings.LastDir ;
  OpenDialog1.FileName := '' ;
  if OpenDialog1.Execute
    then
      LoadBin(OpenDialog1.FileName) ;
end;

procedure TMainForm.miSaveBinClick(Sender: TObject);
begin
  if FFileName = ''
    then
      miSaveBinAsClick(Sender)
    else
      SaveBin(FFileName) ;
end;

procedure TMainForm.miSaveBinAsClick(Sender: TObject);
begin
  FGrid.FinishEdit ;
  SaveDialog1.InitialDir := FSettings.LastDir ;
  SaveDialog1.FileName := ExtractFileName(FFileName) ;
  if SaveDialog1.Execute
    then
      SaveBin(SaveDialog1.FileName) ;
end;

procedure TMainForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if (Length(FileNames) > 0) and CheckSave
    then
      LoadBin(FileNames[0]) ;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := CheckSave ;
end;

procedure TMainForm.miExitClick(Sender: TObject);
begin
  Close ;
end;

{ import / export }

procedure TMainForm.DoImport(atcursor : boolean) ;
var
  dlg : TImportForm ;
  fmt : THexFormat ;
  fn, lastdir : string ;
  pos : TImportPosition ;
  ofs : integer ;
  r   : TImportResult ;
begin
  FGrid.FinishEdit ;
  fmt := FSettings.LastImportFormat ;
  fn := '' ;
  lastdir := FSettings.LastDir ;
  if atcursor
    then
      pos := ipOffset
    else
      pos := ipFileAddress ;
  ofs := FGrid.CursorOffset ;
  dlg := TImportForm.Create(Self) ;
  try
    if not dlg.Execute(fmt, fn, pos, ofs, FGrid.BaseAddress, lastdir)
      then
        exit ;
  finally
    dlg.Free ;
  end ;
  FSettings.LastImportFormat := fmt ;
  FSettings.LastDir := lastdir ;
  Screen.Cursor := crHourGlass ;
  try
    r := ImportFile(FBuf, fmt, fn, pos, ofs, FGrid.BaseAddress) ;
  finally
    Screen.Cursor := crDefault ;
  end ;
  if not r.Ok
    then
      begin
        MessageDlg('Import', 'Import failed: ' + r.Message, mtError, [mbOK], 0) ;
        exit ;
      end ;
  FGrid.DataChanged ;
  FGrid.SelectRange(r.FirstOffset, r.LastOffset) ;
  UpdateMenus ;
  ShowMessageText(r.Message) ;
end ;

procedure TMainForm.miImportClick(Sender: TObject);
begin
  DoImport(false) ;
end;

procedure TMainForm.pmImportClick(Sender: TObject);
begin
  DoImport(true) ;
end;

procedure TMainForm.miExportClick(Sender: TObject);
var
  dlg : TExportForm ;
  p   : TExportParams ;
  msg, lastdir : string ;
begin
  FGrid.FinishEdit ;
  p := Default(TExportParams) ;
  p.Format := FSettings.LastExportFormat ;
  if FGrid.HasSelection
    then
      begin
        p.StartOffset := FGrid.SelStart ;
        p.EndOffset := FGrid.SelEnd ;
      end
    else
      begin
        p.StartOffset := 0 ;
        p.EndOffset := FBuf.Size - 1 ;
      end ;
  p.FileAddress := (FGrid.BaseAddress + p.StartOffset) and $FFFF ;
  p.S9Address := p.FileAddress ;
  p.TapeID := FSettings.TapeID ;
  p.DefineText := FSettings.DefineText ;
  if FFileName <> ''
    then
      p.FileName := ChangeFileExt(FFileName, '.hex') ;
  lastdir := FSettings.LastDir ;
  dlg := TExportForm.Create(Self) ;
  try
    if not dlg.Execute(FBuf, p, lastdir)
      then
        exit ;
  finally
    dlg.Free ;
  end ;
  FSettings.LastExportFormat := p.Format ;
  FSettings.LastDir := lastdir ;
  FSettings.TapeID := p.TapeID ;
  FSettings.DefineText := p.DefineText ;
  msg := ExportRange(FBuf, p) ;
  if msg <> ''
    then
      MessageDlg('Export', 'Export failed: ' + msg, mtError, [mbOK], 0)
    else
      ShowMessageText(Format('Exported %.5X-%.5X as %s to %s',
        [p.StartOffset, p.EndOffset, FormatNames[p.Format],
         ExtractFileName(p.FileName)])) ;
end;

{ edit }

procedure TMainForm.miUndoClick(Sender: TObject);
begin
  FGrid.FinishEdit ;
  FBuf.Undo ;
  FGrid.DataChanged ;
  UpdateMenus ;
end;

procedure TMainForm.miRedoClick(Sender: TObject);
begin
  FGrid.FinishEdit ;
  FBuf.Redo ;
  FGrid.DataChanged ;
  UpdateMenus ;
end;

procedure TMainForm.miCopyClick(Sender: TObject);
var
  n : integer ;
begin
  FGrid.FinishEdit ;
  n := FGrid.SelEnd - FGrid.SelStart + 1 ;
  Clipboard.AsText := BytesToHexText(FBuf.DataPtr + FGrid.SelStart, n) ;
  ShowMessageText(Format('Copied %d bytes as hex text', [n])) ;
end;

procedure TMainForm.miPasteClick(Sender: TObject);
var
  bytes : TBytes ;
  ofs, room : integer ;
begin
  FGrid.FinishEdit ;
  if not HexTextToBytes(Clipboard.AsText, bytes)
    then
      begin
        MessageDlg('Paste', 'The clipboard does not contain hex bytes ' +
                   '(like A9 00 85 F1).', mtInformation, [mbOK], 0) ;
        exit ;
      end ;
  ofs := FGrid.SelStart ;
  room := FBuf.Size - ofs ;
  if Length(bytes) > room
    then
      begin
        if MessageDlg('Paste', Format('Only %d of %d bytes fit before the ' +
                      'end of the buffer. Paste these?', [room, Length(bytes)]),
                      mtConfirmation, [mbYes, mbNo], 0) <> mrYes
          then
            exit ;
        SetLength(bytes, room) ;
      end ;
  FBuf.Write(ofs, bytes) ;
  FGrid.DataChanged ;
  FGrid.SelectRange(ofs, ofs + Length(bytes) - 1) ;
  ShowMessageText(Format('Pasted %d bytes at %.5X', [Length(bytes), ofs])) ;
end;

procedure TMainForm.miSelectAllClick(Sender: TObject);
begin
  FGrid.SelectAll ;
end;

procedure TMainForm.miFillClick(Sender: TObject);
var
  s : string ;
  b : byte ;
  first, last : integer ;
begin
  FGrid.FinishEdit ;
  if not FGrid.HasSelection
    then
      begin
        MessageDlg('Fill', 'Select a range first.', mtInformation, [mbOK], 0) ;
        exit ;
      end ;
  first := FGrid.SelStart ;
  last := FGrid.SelEnd ;
  s := IntToHex(FBuf.EmptyByte, 2) ;
  repeat
    if not InputQuery('Fill selection',
             Format('Fill %.5X-%.5X with byte (hex, e.g. FF) or character ' +
                    '(e.g. ''A''):', [first, last]), s)
      then
        exit ;
    if ParseByteValue(s, b)
      then
        break ;
    MessageDlg('Fill', 'Enter a hex byte (00-FF) or a character in quotes.',
               mtError, [mbOK], 0) ;
  until false ;
  FBuf.Fill(first, last - first + 1, b) ;
  FGrid.DataChanged ;
  ShowMessageText(Format('Filled %.5X-%.5X with $%.2X', [first, last, b])) ;
end;

function TMainForm.AskHex(const acaption, aprompt : string ; var value : integer ;
                          maxvalue : integer) : boolean ;
var
  s : string ;
  v : integer ;
begin
  Result := false ;
  s := IntToHex(value, 1) ;
  repeat
    if not InputQuery(acaption, aprompt, s)
      then
        exit ;
    if ParseHex(s, v) and (v >= 0) and (v <= maxvalue)
      then
        break ;
    MessageDlg(acaption, Format('Enter a hex number from 0 to %X.', [maxvalue]),
               mtError, [mbOK], 0) ;
  until false ;
  value := v ;
  Result := true ;
end ;

procedure TMainForm.miGotoClick(Sender: TObject);
var
  v : integer ;
begin
  FGrid.FinishEdit ;
  if FGrid.BaseAddress = 0
    then
      begin
        v := FGrid.CursorOffset ;
        if AskHex('Go to', 'Offset (hex):', v, FBuf.Size - 1)
          then
            FGrid.GotoOffset(v) ;
      end
    else
      begin
        v := FGrid.BaseAddress + FGrid.CursorOffset ;
        if not AskHex('Go to', Format('Address (hex, %X-%X):',
                      [FGrid.BaseAddress, FGrid.BaseAddress + FBuf.Size - 1]),
                      v, FGrid.BaseAddress + FBuf.Size - 1)
          then
            exit ;
        if v < FGrid.BaseAddress
          then
            MessageDlg('Go to', 'Address is below the base address.', mtError,
                       [mbOK], 0)
          else
            FGrid.GotoOffset(v - FGrid.BaseAddress) ;
      end ;
end;

{ search }

procedure TMainForm.DoSearch(backward : boolean ; from : integer) ;
var
  spec : TSearchSpec ;
  found : integer ;
  wrapped : boolean ;
begin
  spec := FSearch ;
  spec.Backward := backward ;
  if not spec.InSelection
    then
      begin
        spec.RangeStart := 0 ;
        spec.RangeEnd := FBuf.Size - 1 ;
      end ;
  Screen.Cursor := crHourGlass ;
  try
    found := SearchData(FBuf.DataPtr, spec, from, wrapped) ;
  finally
    Screen.Cursor := crDefault ;
  end ;
  if found < 0
    then
      begin
        ShowMessageText('Not found: ' + spec.Text) ;
        MessageDlg('Find', 'Not found: ' + spec.Text, mtInformation, [mbOK], 0) ;
        exit ;
      end ;
  FGrid.SelectRange(found, found + Length(spec.Pattern) - 1) ;
  if wrapped
    then
      ShowMessageText('Found at ' + OffsetText(found) + ' (search wrapped)')
    else
      ShowMessageText('Found at ' + OffsetText(found)) ;
end ;

procedure TMainForm.miFindClick(Sender: TObject);
var
  dlg : TFindForm ;
  from : integer ;
begin
  FGrid.FinishEdit ;
  dlg := TFindForm.Create(Self) ;
  try
    if not dlg.Execute(FSearch, FSettings.SearchHistory, FGrid.HasSelection)
      then
        exit ;
  finally
    dlg.Free ;
  end ;
  FSettings.AddSearch(FSearch.Text) ;
  if FSearch.InSelection
    then
      begin
        FSearch.RangeStart := FGrid.SelStart ;
        FSearch.RangeEnd := FGrid.SelEnd ;
        if FSearch.Backward
          then
            from := FSearch.RangeEnd
          else
            from := FSearch.RangeStart ;
      end
    else
      from := FGrid.CursorOffset ;
  DoSearch(FSearch.Backward, from) ;
end;

procedure TMainForm.miFindNextClick(Sender: TObject);
begin
  FGrid.FinishEdit ;
  if Length(FSearch.Pattern) = 0
    then
      miFindClick(Sender)
    else
      DoSearch(false, FGrid.SelStart + 1) ;
end;

procedure TMainForm.miFindPrevClick(Sender: TObject);
begin
  FGrid.FinishEdit ;
  if Length(FSearch.Pattern) = 0
    then
      miFindClick(Sender)
    else
      DoSearch(true, FGrid.SelStart - 1) ;
end;

procedure TMainForm.miChecksumClick(Sender: TObject);
var
  first, n : integer ;
  what : string ;
begin
  FGrid.FinishEdit ;
  if FGrid.HasSelection
    then
      begin
        first := FGrid.SelStart ;
        n := FGrid.SelEnd - first + 1 ;
        what := Format('Selection %.5X-%.5X', [first, FGrid.SelEnd]) ;
      end
    else
      begin
        first := 0 ;
        n := FBuf.Size ;
        what := 'Whole buffer (' + BufferSizeText(n) + ')' ;
      end ;
  MessageDlg('Checksum', Format('%s, %d bytes' + LineEnding + LineEnding +
             'Sum (16 bit):  %.4X' + LineEnding +
             'CRC32:         %.8X',
             [what, n, Checksum16(FBuf.DataPtr + first, n),
              CRC32(FBuf.DataPtr + first, n)]), mtInformation, [mbOK], 0) ;
end;

{ options }

procedure TMainForm.SizeItemClick(Sender : TObject) ;
var
  newsize : integer ;
begin
  FGrid.FinishEdit ;
  newsize := TMenuItem(Sender).Tag ;
  if newsize = FBuf.Size
    then
      exit ;
  if (newsize < FBuf.Size) and
     not FBuf.IsEmptyRange(newsize, FBuf.Size - newsize) and
     (MessageDlg('Buffer size', Format('Offset %.5X-%.5X holds data that will ' +
                 'be removed. Continue? (Undo is possible)',
                 [newsize, FBuf.Size - 1]), mtWarning, [mbYes, mbNo], 0) <> mrYes)
    then
      begin
        UpdateMenus ;
        exit ;
      end ;
  FBuf.Resize(newsize) ;
  FGrid.DataChanged ;
  UpdateMenus ;
  ShowMessageText('Buffer size now ' + BufferSizeText(FBuf.Size)) ;
end ;

procedure TMainForm.miPerRowClick(Sender: TObject);
begin
  FGrid.FinishEdit ;
  if Sender = miPerRow32
    then
      FGrid.BytesPerRow := 32
    else
      FGrid.BytesPerRow := 16 ;
  FitWidth ;
  UpdateMenus ;
end;

procedure TMainForm.FontSizeClick(Sender : TObject) ;
begin
  FGrid.Font.Size := TMenuItem(Sender).Tag ;
  FGrid.UpdateLayout ;
  FitWidth ;
  UpdateMenus ;
end ;

procedure TMainForm.miEmptyByteClick(Sender: TObject);
var
  v : integer ;
begin
  v := FBuf.EmptyByte ;
  if AskHex('Empty byte', 'Value of an empty byte (hex, default FF):', v, $FF)
    then
      FBuf.EmptyByte := v ;
  UpdateMenus ;
end;

procedure TMainForm.miBaseAddressClick(Sender: TObject);
var
  v : integer ;
begin
  v := FGrid.BaseAddress ;
  if AskHex('Base address', 'Address of offset 0, for display, import and ' +
            'export (hex, e.g. E000):', v, $FFFFFF)
    then
      FGrid.BaseAddress := v ;
  FitWidth ;
  UpdateMenus ;
end;

procedure TMainForm.miStripBit7Click(Sender: TObject);
begin
  FGrid.StripBit7 := not FGrid.StripBit7 ;
  UpdateMenus ;
end;

procedure TMainForm.ColorItemClick(Sender : TObject) ;
var
  c : TGridColors ;
  i : integer ;
begin
  i := TMenuItem(Sender).Tag ;
  c := FGrid.Colors ;
  ColorDialog1.Color := ColorOf(c, i) ;
  ColorDialog1.Title := 'Color: ' + ColorItemNames[i] ;
  if ColorDialog1.Execute
    then
      begin
        SetColorOf(c, i, ColorDialog1.Color) ;
        FGrid.Colors := c ;
      end ;
end ;

procedure TMainForm.DefaultColorsClick(Sender : TObject) ;
begin
  FGrid.Colors := DefaultColors ;
end ;

{ help }

procedure TMainForm.miHelpItemClick(Sender: TObject);
var
  f : TForm ;
  m : TMemo ;
begin
  f := TForm.CreateNew(Self) ;
  try
    f.Caption := AppName + ' help' ;
    f.Position := poOwnerFormCenter ;
    f.Width := 620 ;
    f.Height := 520 ;
    m := TMemo.Create(f) ;
    m.Parent := f ;
    m.Align := alClient ;
    m.ReadOnly := true ;
    m.ScrollBars := ssVertical ;
    m.Font.Name := FGrid.Font.Name ;
    m.Lines.Text :=
      AppVersion + LineEnding +
      LineEnding +
      'Edit the data of a buffer of 2K .. 1M (EPROM sizes).' + LineEnding +
      'Click a cell in the hex or ASCII part and type: hex digits in the' + LineEnding +
      'hex part, characters in the ASCII part.' + LineEnding +
      LineEnding +
      'Keys' + LineEnding +
      '  Cursor keys         move (Shift: select)' + LineEnding +
      '  Home / End          start / end of row' + LineEnding +
      '  Ctrl+Home / End     start / end of buffer' + LineEnding +
      '  PgUp / PgDn         one page up / down' + LineEnding +
      '  Tab                 hex <-> ASCII part' + LineEnding +
      '  Delete              delete byte or selection, rest moves down' + LineEnding +
      '  Insert              insert mode: insert an empty cell' + LineEnding +
      '    hex part          type 2 hex digits, Tab adds the next cell' + LineEnding +
      '    ASCII part        every character is inserted' + LineEnding +
      '    Enter / Esc       end insert mode' + LineEnding +
      '  Esc                 cancel half typed byte / clear selection' + LineEnding +
      '  Ctrl+Z / Ctrl+Y     undo / redo (10 deep)' + LineEnding +
      '  Ctrl+C / Ctrl+V     copy / paste as hex text' + LineEnding +
      '  Ctrl+A              select all' + LineEnding +
      '  Ctrl+G              go to offset (or address with base address)' + LineEnding +
      '  Ctrl+F, F3, Shift+F3  find, find next, find previous' + LineEnding +
      LineEnding +
      'Mouse' + LineEnding +
      '  Click               cursor; drag or Shift+click selects' + LineEnding +
      '  Right click         import here, fill, export selection, copy,' + LineEnding +
      '                      paste, checksum' + LineEnding +
      LineEnding +
      'Files' + LineEnding +
      '  Load/Save BIN       the whole buffer as binary file, up to 1M' + LineEnding +
      '  Import              BIN, PRG, hex, Intel hex, MOS/TIM papertape,' + LineEnding +
      '                      Motorola S-record, Apple 1 hex, KIM tape.' + LineEnding +
      '                      Only the bytes in the file are written.' + LineEnding +
      '  Export              the selection (or whole buffer) in one of these' + LineEnding +
      '                      formats or as Define source; at most 64K with a' + LineEnding +
      '                      16 bit file address, BIN any size.' + LineEnding +
      LineEnding +
      'Options' + LineEnding +
      '  Empty byte          value for new, inserted and freed bytes ($FF)' + LineEnding +
      '  Base address        address of offset 0 (e.g. E000 for a ROM),' + LineEnding +
      '                      used for display, go to, import and export' + LineEnding +
      '  Strip bit 7         show $A0-$FE as ASCII without bit 7' + LineEnding +
      LineEnding +
      'Settings are kept in ' + FSettings.FileName ;
    f.ShowModal ;
  finally
    f.Free ;
  end ;
end;

procedure TMainForm.miAboutClick(Sender: TObject);
begin
  MessageDlg('About ' + AppName,
             AppVersion + LineEnding + AppAuthor + LineEnding + LineEnding +
             'Import, edit and export the data of a data buffer in binary ' +
             'form.' + LineEnding +
             'Hex formats through the Convert8bithex units.' + LineEnding +
             LineEnding + 'MIT License', mtInformation, [mbOK], 0) ;
end;

end.
