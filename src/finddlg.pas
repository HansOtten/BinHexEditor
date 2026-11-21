unit finddlg;

{
  BinHexEditor - find dialog: hex bytes, hex words or ASCII text

  MIT License, Copyright (c) 2026 Hans Otten
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  searching;

type

  { TFindForm }

  TFindForm = class(TForm)
    btnCancel: TButton;
    btnFind: TButton;
    cbBackward: TCheckBox;
    cbBit7: TCheckBox;
    cbCase: TCheckBox;
    cbSelection: TCheckBox;
    cbText: TComboBox;
    cbWrap: TCheckBox;
    lblSearch: TLabel;
    rgKind: TRadioGroup;
    procedure btnFindClick(Sender: TObject);
    procedure rgKindClick(Sender: TObject);
  private
    procedure UpdateControls ;
    function  GetSpec(var spec : TSearchSpec) : string ;
  public
    function Execute(var spec : TSearchSpec ; history : TStrings ;
                     hasselection : boolean) : boolean ;
  end;

implementation

{$R *.lfm}

{ TFindForm }

procedure TFindForm.UpdateControls ;
begin
  cbCase.Enabled := rgKind.ItemIndex = Ord(skText) ;
  cbBit7.Enabled := rgKind.ItemIndex = Ord(skText) ;
end ;

procedure TFindForm.rgKindClick(Sender: TObject);
begin
  UpdateControls ;
end;

function TFindForm.GetSpec(var spec : TSearchSpec) : string ;
begin
  spec.Kind := TSearchKind(rgKind.ItemIndex) ;
  spec.Text := cbText.Text ;
  spec.CaseSensitive := cbCase.Checked ;
  spec.IgnoreBit7 := cbBit7.Checked ;
  spec.InSelection := cbSelection.Enabled and cbSelection.Checked ;
  spec.Backward := cbBackward.Checked ;
  spec.Wrap := cbWrap.Checked ;
  Result := ParsePattern(spec) ;
end ;

procedure TFindForm.btnFindClick(Sender: TObject);
var
  spec : TSearchSpec ;
  msg : string ;
begin
  spec := Default(TSearchSpec) ;
  msg := GetSpec(spec) ;
  if msg <> ''
    then
      begin
        MessageDlg('Find', msg, mtError, [mbOK], 0) ;
        cbText.SetFocus ;
        exit ;
      end ;
  ModalResult := mrOK ;
end;

function TFindForm.Execute(var spec : TSearchSpec ; history : TStrings ;
                           hasselection : boolean) : boolean ;
begin
  rgKind.ItemIndex := Ord(spec.Kind) ;
  cbText.Items.Assign(history) ;
  cbText.Text := spec.Text ;
  cbCase.Checked := spec.CaseSensitive ;
  cbBit7.Checked := spec.IgnoreBit7 ;
  cbSelection.Enabled := hasselection ;
  cbSelection.Checked := hasselection and spec.InSelection ;
  cbBackward.Checked := spec.Backward ;
  cbWrap.Checked := spec.Wrap ;
  UpdateControls ;
  ActiveControl := cbText ;
  Result := ShowModal = mrOK ;
  if Result
    then
      GetSpec(spec) ;
end ;

end.
