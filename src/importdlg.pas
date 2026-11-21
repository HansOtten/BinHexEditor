unit importdlg;

{
  BinHexEditor - import dialog: format, file and position

  MIT License, Copyright (c) 2026 Hans Otten
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  importexport, searching;

type

  { TImportForm }

  TImportForm = class(TForm)
    btnBrowse: TButton;
    btnCancel: TButton;
    btnOK: TButton;
    cbFormat: TComboBox;
    edFile: TEdit;
    edOffset: TEdit;
    lblFile: TLabel;
    lblFormat: TLabel;
    lblInfo: TLabel;
    OpenDialog1: TOpenDialog;
    rgPosition: TRadioGroup;
    procedure btnBrowseClick(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure cbFormatChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure rgPositionClick(Sender: TObject);
  private
    FBase : integer ;
    function SelectedFormat : THexFormat ;
    procedure UpdateControls ;
  public
    { true if OK; fmt/filename/apos/offset are in and out }
    function Execute(var fmt : THexFormat ; var filename : string ;
                     var apos : TImportPosition ; var offset : integer ;
                     baseaddress : integer ; var lastdir : string) : boolean ;
  end;

implementation

{$R *.lfm}

{ TImportForm }

procedure TImportForm.FormCreate(Sender: TObject);
var
  f : THexFormat ;
begin
  cbFormat.Items.Clear ;
  for f := Low(THexFormat) to High(THexFormat) do
    if CanImport(f)
      then
        cbFormat.Items.AddObject(FormatNames[f], TObject(PtrInt(Ord(f)))) ;
  cbFormat.ItemIndex := 0 ;
end;

function TImportForm.SelectedFormat : THexFormat ;
begin
  if cbFormat.ItemIndex < 0
    then
      Result := hfBIN
    else
      Result := THexFormat(PtrInt(cbFormat.Items.Objects[cbFormat.ItemIndex])) ;
end ;

procedure TImportForm.UpdateControls ;
begin
  edOffset.Enabled := rgPosition.ItemIndex = 1 ;
  if HasNoAddress(SelectedFormat)
    then
      lblInfo.Caption := 'This format has no address: "at the address in the ' +
                         'file" places the data at offset 0.'
    else
      if FBase <> 0
        then
          lblInfo.Caption := Format('Base address is $%X: address in the file ' +
                             'minus base address gives the offset.', [FBase])
        else
          lblInfo.Caption := 'Only the bytes in the file are written, the rest ' +
                             'of the buffer stays intact.' ;
end ;

procedure TImportForm.cbFormatChange(Sender: TObject);
begin
  UpdateControls ;
end;

procedure TImportForm.rgPositionClick(Sender: TObject);
begin
  UpdateControls ;
end;

procedure TImportForm.btnBrowseClick(Sender: TObject);
begin
  OpenDialog1.Filter := FormatFilters[SelectedFormat] + AllFilesFilter ;
  OpenDialog1.FilterIndex := 1 ;
  if edFile.Text <> ''
    then
      OpenDialog1.InitialDir := ExtractFilePath(edFile.Text) ;
  if OpenDialog1.Execute
    then
      edFile.Text := OpenDialog1.FileName ;
end;

procedure TImportForm.btnOKClick(Sender: TObject);
var
  v : integer ;
begin
  if not FileExists(edFile.Text)
    then
      begin
        MessageDlg('Import', 'File not found: ' + edFile.Text, mtError,
                   [mbOK], 0) ;
        edFile.SetFocus ;
        exit ;
      end ;
  if (rgPosition.ItemIndex = 1) and not ParseHex(edOffset.Text, v)
    then
      begin
        MessageDlg('Import', 'Enter the offset as a hex number, e.g. 1000',
                   mtError, [mbOK], 0) ;
        edOffset.SetFocus ;
        exit ;
      end ;
  ModalResult := mrOK ;
end;

function TImportForm.Execute(var fmt : THexFormat ; var filename : string ;
                             var apos : TImportPosition ;
                             var offset : integer ; baseaddress : integer ;
                             var lastdir : string) : boolean ;
var
  i : integer ;
begin
  FBase := baseaddress ;
  for i := 0 to cbFormat.Items.Count - 1 do
    if THexFormat(PtrInt(cbFormat.Items.Objects[i])) = fmt
      then
        cbFormat.ItemIndex := i ;
  edFile.Text := filename ;
  OpenDialog1.InitialDir := lastdir ;
  if apos = ipOffset
    then
      rgPosition.ItemIndex := 1
    else
      rgPosition.ItemIndex := 0 ;
  edOffset.Text := IntToHex(offset, 5) ;
  UpdateControls ;
  Result := ShowModal = mrOK ;
  if Result
    then
      begin
        fmt := SelectedFormat ;
        filename := edFile.Text ;
        lastdir := ExtractFilePath(filename) ;
        if rgPosition.ItemIndex = 1
          then
            begin
              apos := ipOffset ;
              ParseHex(edOffset.Text, offset) ;
            end
          else
            apos := ipFileAddress ;
      end ;
end ;

end.
