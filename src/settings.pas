unit settings;

{
  BinHexEditor - options and last used values, kept in an ini file
  (GetAppConfigDir/BinHexEditor.ini)

  MIT License, Copyright (c) 2026 Hans Otten
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, Graphics, hexgrid, editbuffer, importexport,
  searching;

const
  MaxSearchHistory = 10 ;

type
  TAppSettings = class
  public
    BufferSize       : integer ;
    BytesPerRow      : integer ;
    EmptyByte        : byte ;
    BaseAddress      : integer ;
    StripBit7        : boolean ;
    Colors           : TGridColors ;
    FontSize         : integer ;
    LastDir          : string ;
    LastImportFormat : THexFormat ;
    LastExportFormat : THexFormat ;
    TapeID           : byte ;
    DefineText       : string ;
    SearchKind       : TSearchKind ;
    SearchCase       : boolean ;
    SearchBit7       : boolean ;
    SearchWrap       : boolean ;
    SearchHistory    : TStringList ;
    WindowWidth,
    WindowHeight     : integer ;
    constructor Create ;
    destructor Destroy ; override ;
    procedure Load ;
    procedure Save ;
    procedure AddSearch(const s : string) ;
    function  FileName : string ;
  end ;

implementation

const
  ColorNames : array[0..6] of string =
    ('Address', 'Hex', 'Ascii', 'Header', 'Cursor', 'Selection', 'Modified') ;

constructor TAppSettings.Create ;
begin
  inherited Create ;
  SearchHistory := TStringList.Create ;
  BufferSize := DefaultBufferSize ;
  BytesPerRow := 16 ;
  EmptyByte := $FF ;
  BaseAddress := 0 ;
  StripBit7 := false ;
  Colors := DefaultColors ;
  FontSize := 10 ;
  LastDir := '' ;
  LastImportFormat := hfIntel ;
  LastExportFormat := hfIntel ;
  TapeID := 1 ;
  DefineText := '.byte $' ;
  SearchKind := skHexBytes ;
  SearchCase := false ;
  SearchBit7 := false ;
  SearchWrap := true ;
  WindowWidth := 0 ;
  WindowHeight := 0 ;
end ;

destructor TAppSettings.Destroy ;
begin
  SearchHistory.Free ;
  inherited Destroy ;
end ;

function TAppSettings.FileName : string ;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(false)) +
            'BinHexEditor.ini' ;
end ;

function ColorPtr(var c : TGridColors ; index : integer) : PColor ;
begin
  case index of
    0 : Result := @c.Address ;
    1 : Result := @c.Hex ;
    2 : Result := @c.Ascii ;
    3 : Result := @c.Header ;
    4 : Result := @c.Cursor ;
    5 : Result := @c.Selection ;
  else
    Result := @c.Modified ;
  end ;
end ;

procedure TAppSettings.Load ;
var
  ini : TIniFile ;
  i, v : integer ;
  s : string ;
begin
  if not FileExists(FileName)
    then
      exit ;
  try
    ini := TIniFile.Create(FileName) ;
    try
      v := ini.ReadInteger('Buffer', 'Size', BufferSize) ;
      if RoundUpBufferSize(v) = v
        then
          BufferSize := v ;
      v := ini.ReadInteger('Buffer', 'BytesPerRow', BytesPerRow) ;
      if v in [16, 32]
        then
          BytesPerRow := v ;
      EmptyByte := ini.ReadInteger('Buffer', 'EmptyByte', EmptyByte) and $FF ;
      BaseAddress := ini.ReadInteger('Buffer', 'BaseAddress', BaseAddress) ;
      StripBit7 := ini.ReadBool('Display', 'StripBit7', StripBit7) ;
      v := ini.ReadInteger('Display', 'FontSize', FontSize) ;
      if (v >= 6) and (v <= 24)
        then
          FontSize := v ;
      for i := 0 to High(ColorNames) do
        ColorPtr(Colors, i)^ := ini.ReadInteger('Colors', ColorNames[i],
                                                ColorPtr(Colors, i)^) ;
      LastDir := ini.ReadString('Files', 'LastDir', LastDir) ;
      LastImportFormat := FormatFromKey(ini.ReadString('Files',
                            'ImportFormat', ''), LastImportFormat) ;
      LastExportFormat := FormatFromKey(ini.ReadString('Files',
                            'ExportFormat', ''), LastExportFormat) ;
      TapeID := ini.ReadInteger('Export', 'KIMTapeID', TapeID) and $FF ;
      DefineText := ini.ReadString('Export', 'DefineText', DefineText) ;
      v := ini.ReadInteger('Search', 'Kind', Ord(SearchKind)) ;
      if (v >= Ord(Low(TSearchKind))) and (v <= Ord(High(TSearchKind)))
        then
          SearchKind := TSearchKind(v) ;
      SearchCase := ini.ReadBool('Search', 'CaseSensitive', SearchCase) ;
      SearchBit7 := ini.ReadBool('Search', 'IgnoreBit7', SearchBit7) ;
      SearchWrap := ini.ReadBool('Search', 'Wrap', SearchWrap) ;
      SearchHistory.Clear ;
      for i := 1 to MaxSearchHistory do
        begin
          s := ini.ReadString('Search', 'History' + IntToStr(i), '') ;
          if s <> ''
            then
              SearchHistory.Add(s) ;
        end ;
      WindowWidth := ini.ReadInteger('Window', 'Width', 0) ;
      WindowHeight := ini.ReadInteger('Window', 'Height', 0) ;
    finally
      ini.Free ;
    end ;
  except
    on E: Exception do ;   { bad ini file: use defaults }
  end ;
end ;

procedure TAppSettings.Save ;
var
  ini : TIniFile ;
  i : integer ;
begin
  try
    ForceDirectories(ExtractFilePath(FileName)) ;
    ini := TIniFile.Create(FileName) ;
    try
      ini.WriteInteger('Buffer', 'Size', BufferSize) ;
      ini.WriteInteger('Buffer', 'BytesPerRow', BytesPerRow) ;
      ini.WriteInteger('Buffer', 'EmptyByte', EmptyByte) ;
      ini.WriteInteger('Buffer', 'BaseAddress', BaseAddress) ;
      ini.WriteBool('Display', 'StripBit7', StripBit7) ;
      ini.WriteInteger('Display', 'FontSize', FontSize) ;
      for i := 0 to High(ColorNames) do
        ini.WriteInteger('Colors', ColorNames[i], ColorPtr(Colors, i)^) ;
      ini.WriteString('Files', 'LastDir', LastDir) ;
      ini.WriteString('Files', 'ImportFormat', FormatKeys[LastImportFormat]) ;
      ini.WriteString('Files', 'ExportFormat', FormatKeys[LastExportFormat]) ;
      ini.WriteInteger('Export', 'KIMTapeID', TapeID) ;
      ini.WriteString('Export', 'DefineText', DefineText) ;
      ini.WriteInteger('Search', 'Kind', Ord(SearchKind)) ;
      ini.WriteBool('Search', 'CaseSensitive', SearchCase) ;
      ini.WriteBool('Search', 'IgnoreBit7', SearchBit7) ;
      ini.WriteBool('Search', 'Wrap', SearchWrap) ;
      for i := 1 to MaxSearchHistory do
        if i <= SearchHistory.Count
          then
            ini.WriteString('Search', 'History' + IntToStr(i),
                            SearchHistory[i - 1])
          else
            ini.DeleteKey('Search', 'History' + IntToStr(i)) ;
      ini.WriteInteger('Window', 'Width', WindowWidth) ;
      ini.WriteInteger('Window', 'Height', WindowHeight) ;
    finally
      ini.Free ;
    end ;
  except
    on E: Exception do ;   { settings are not essential }
  end ;
end ;

procedure TAppSettings.AddSearch(const s : string) ;
var
  i : integer ;
begin
  if s = ''
    then
      exit ;
  i := SearchHistory.IndexOf(s) ;
  if i >= 0
    then
      SearchHistory.Delete(i) ;
  SearchHistory.Insert(0, s) ;
  while SearchHistory.Count > MaxSearchHistory do
    SearchHistory.Delete(SearchHistory.Count - 1) ;
end ;

end.
