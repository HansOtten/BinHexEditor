unit exportdlg;

{
  BinHexEditor - export dialog: format, file, range, file address and the
  extra input some formats need

  MIT License, Copyright (c) 2026 Hans Otten
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  editbuffer, importexport, searching;

type

  { TExportForm }

  TExportForm = class(TForm)
    btnBrowse: TButton;
    btnCancel: TButton;
    btnOK: TButton;
    cbFormat: TComboBox;
    edDefine: TEdit;
    edEnd: TEdit;
    edFile: TEdit;
    edFileAddr: TEdit;
    edS9: TEdit;
    edStart: TEdit;
    edTapeID: TEdit;
    lblDefine: TLabel;
    lblEnd: TLabel;
    lblFile: TLabel;
    lblFileAddr: TLabel;
    lblFormat: TLabel;
    lblLength: TLabel;
    lblS9: TLabel;
    lblStart: TLabel;
    lblTapeID: TLabel;
    SaveDialog1: TSaveDialog;
    procedure btnBrowseClick(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure cbFormatChange(Sender: TObject);
    procedure edRangeChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FBuf : TEditBuffer ;
    function  SelectedFormat : THexFormat ;
    procedure UpdateControls ;
    function  GetParams(out p : TExportParams ; out msg : string) : boolean ;
  public
    function Execute(buf : TEditBuffer ; var p : TExportParams ;
                     var lastdir : string) : boolean ;
  end;

implementation

{$R *.lfm}

{ TExportForm }

procedure TExportForm.FormCreate(Sender: TObject);
var
  f : THexFormat ;
begin
  cbFormat.Items.Clear ;
  for f := Low(THexFormat) to High(THexFormat) do
    cbFormat.Items.AddObject(FormatNames[f], TObject(PtrInt(Ord(f)))) ;
  cbFormat.ItemIndex := 0 ;
end;

function TExportForm.SelectedFormat : THexFormat ;
begin
  if cbFormat.ItemIndex < 0
    then
      Result := hfBIN
    else
      Result := THexFormat(PtrInt(cbFormat.Items.Objects[cbFormat.ItemIndex])) ;
end ;

procedure TExportForm.UpdateControls ;
var
  f : THexFormat ;
  s, e : integer ;
begin
  f := SelectedFormat ;
  edFileAddr.Enabled := f <> hfBIN ;
  lblFileAddr.Enabled := edFileAddr.Enabled ;
  edTapeID.Enabled := f = hfKIM ;
  lblTapeID.Enabled := edTapeID.Enabled ;
  edDefine.Enabled := f = hfDefine ;
  lblDefine.Enabled := edDefine.Enabled ;
  edS9.Enabled := f = hfSrec ;
  lblS9.Enabled := edS9.Enabled ;
  if ParseHex(edStart.Text, s) and ParseHex(edEnd.Text, e) and (e >= s)
    then
      lblLength.Caption := Format('Length %d bytes ($%X)', [e - s + 1, e - s + 1])
    else
      lblLength.Caption := 'Length ?' ;
end ;

procedure TExportForm.cbFormatChange(Sender: TObject);
begin
  UpdateControls ;
end;

procedure TExportForm.edRangeChange(Sender: TObject);
begin
  UpdateControls ;
end;

procedure TExportForm.btnBrowseClick(Sender: TObject);
begin
  SaveDialog1.Filter := FormatFilters[SelectedFormat] + AllFilesFilter ;
  SaveDialog1.FilterIndex := 1 ;
  if edFile.Text <> ''
    then
      begin
        SaveDialog1.InitialDir := ExtractFilePath(edFile.Text) ;
        SaveDialog1.FileName := ExtractFileName(edFile.Text) ;
      end ;
  if SaveDialog1.Execute
    then
      edFile.Text := SaveDialog1.FileName ;
end;

function TExportForm.GetParams(out p : TExportParams ; out msg : string) : boolean ;
var
  v : integer ;
begin
  Result := false ;
  msg := '' ;
  p := Default(TExportParams) ;
  p.Format := SelectedFormat ;
  p.FileName := Trim(edFile.Text) ;
  if not ParseHex(edStart.Text, p.StartOffset)
    then
      begin
        msg := 'Start offset must be a hex number' ;
        exit ;
      end ;
  if not ParseHex(edEnd.Text, p.EndOffset)
    then
      begin
        msg := 'End offset must be a hex number' ;
        exit ;
      end ;
  if not ParseHex(edFileAddr.Text, p.FileAddress)
    then
      begin
        msg := 'File address must be a hex number' ;
        exit ;
      end ;
  if not ParseHex(edTapeID.Text, v) or (v > $FF)
    then
      begin
        msg := 'Tape ID must be a hex byte, e.g. 01' ;
        exit ;
      end ;
  p.TapeID := v ;
  p.DefineText := edDefine.Text ;
  if not ParseHex(edS9.Text, p.S9Address)
    then
      begin
        msg := 'S9 start address must be a hex number' ;
        exit ;
      end ;
  msg := CheckExport(FBuf, p) ;
  Result := msg = '' ;
end ;

procedure TExportForm.btnOKClick(Sender: TObject);
var
  p : TExportParams ;
  msg : string ;
begin
  if not GetParams(p, msg)
    then
      begin
        MessageDlg('Export', msg, mtError, [mbOK], 0) ;
        exit ;
      end ;
  if FileExists(p.FileName) and
     (MessageDlg('Export', p.FileName + ' exists. Overwrite?', mtConfirmation,
                 [mbYes, mbNo], 0) <> mrYes)
    then
      exit ;
  ModalResult := mrOK ;
end;

function TExportForm.Execute(buf : TEditBuffer ; var p : TExportParams ;
                             var lastdir : string) : boolean ;
var
  i : integer ;
  msg : string ;
begin
  FBuf := buf ;
  for i := 0 to cbFormat.Items.Count - 1 do
    if THexFormat(PtrInt(cbFormat.Items.Objects[i])) = p.Format
      then
        cbFormat.ItemIndex := i ;
  edFile.Text := p.FileName ;
  SaveDialog1.InitialDir := lastdir ;
  edStart.Text := IntToHex(p.StartOffset, 5) ;
  edEnd.Text := IntToHex(p.EndOffset, 5) ;
  edFileAddr.Text := IntToHex(p.FileAddress, 4) ;
  edTapeID.Text := IntToHex(p.TapeID, 2) ;
  edDefine.Text := p.DefineText ;
  edS9.Text := IntToHex(p.S9Address, 4) ;
  UpdateControls ;
  Result := ShowModal = mrOK ;
  if Result
    then
      begin
        GetParams(p, msg) ;
        lastdir := ExtractFilePath(p.FileName) ;
      end ;
end ;

end.
