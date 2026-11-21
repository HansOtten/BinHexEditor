program BinHexEditor;

{
  BinHexEditor - import, edit and export the data of a data buffer in
  binary form (EPROM images 2K .. 1M)

  Hex formats through the Convert8bithex units loadhexformats and
  savehexformats (folder hexunits).

  MIT License, Copyright (c) 2026 Hans Otten
}

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms,
  hexglobals, loadhexformats, savehexformats,
  editbuffer, importexport, searching, settings, hexgrid,
  main, importdlg, exportdlg, finddlg;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Title := 'BinHexEditor';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
