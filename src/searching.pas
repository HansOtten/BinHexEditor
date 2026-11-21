unit searching;

{
  BinHexEditor - search patterns, search and checksums

  Search for hex bytes (1-16), hex words (1-8, low byte first) or ASCII
  text (1-256, optional case insensitive / ignore bit 7).

  No GUI code, so the unit is also used by the console tests.

  MIT License, Copyright (c) 2026 Hans Otten
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  MaxHexBytes  = 16 ;
  MaxHexWords  = 8 ;
  MaxTextChars = 256 ;

type
  TSearchKind = (skHexBytes, skHexWords, skText) ;

  TSearchSpec = record
    Kind          : TSearchKind ;
    Text          : string ;     { as typed }
    Pattern       : TBytes ;     { parsed }
    CaseSensitive : boolean ;    { text only }
    IgnoreBit7    : boolean ;    { text only }
    Backward      : boolean ;
    Wrap          : boolean ;
    InSelection   : boolean ;
    RangeStart,
    RangeEnd      : integer ;    { search area, inclusive }
  end ;

{ parse spec.Text into spec.Pattern; '' if ok, otherwise error message }
function ParsePattern(var spec : TSearchSpec) : string ;

{ search from offset 'from' (inclusive) in direction of spec;
  result offset of match or -1; wrapped true if search wrapped around }
function SearchData(data : PByte ; const spec : TSearchSpec ;
                    from : integer ; out wrapped : boolean) : integer ;

{ parse hex number, '$' or '0x' prefix allowed; false if invalid }
function ParseHex(const s : string ; out value : integer) : boolean ;
{ parse a byte: hex (FF, $FF) or a character in quotes ('A') }
function ParseByteValue(const s : string ; out value : byte) : boolean ;

function Checksum16(data : PByte ; count : integer) : word ;
function CRC32(data : PByte ; count : integer) : longword ;

{ bytes as hex text 'A9 00 85', and back (blanks, commas, $ ignored) }
function BytesToHexText(data : PByte ; count : integer) : string ;
function HexTextToBytes(const s : string ; out bytes : TBytes) : boolean ;

implementation

function HexDigit(c : char ; out v : integer) : boolean ;
begin
  Result := true ;
  case c of
    '0'..'9' : v := ord(c) - ord('0') ;
    'A'..'F' : v := ord(c) - ord('A') + 10 ;
    'a'..'f' : v := ord(c) - ord('a') + 10 ;
  else
    Result := false ;
  end ;
end ;

function ParseHex(const s : string ; out value : integer) : boolean ;
var
  t : string ;
  i, v : integer ;
begin
  Result := false ;
  value := 0 ;
  t := Trim(s) ;
  if (t <> '') and (t[1] = '$')
    then
      Delete(t, 1, 1)
    else
      if (Length(t) > 2) and (t[1] = '0') and (t[2] in ['x', 'X'])
        then
          Delete(t, 1, 2) ;
  if (t = '') or (Length(t) > 7)
    then
      exit ;
  for i := 1 to Length(t) do
    begin
      if not HexDigit(t[i], v)
        then
          exit ;
      value := value * 16 + v ;
    end ;
  Result := true ;
end ;

function ParseByteValue(const s : string ; out value : byte) : boolean ;
var
  t : string ;
  v : integer ;
begin
  Result := false ;
  value := 0 ;
  t := Trim(s) ;
  if (Length(t) = 3) and (t[1] in ['''', '"']) and (t[3] = t[1])
    then
      begin
        value := ord(t[2]) ;
        exit(true) ;
      end ;
  if ParseHex(t, v) and (v >= 0) and (v <= 255)
    then
      begin
        value := v ;
        Result := true ;
      end ;
end ;

{ hex digits only, separators removed }
function CleanHex(const s : string ; out digits : string) : boolean ;
var
  i, v : integer ;
begin
  Result := false ;
  digits := '' ;
  for i := 1 to Length(s) do
    if s[i] in [' ', ',', '$', #9]
      then
        continue
      else
        if HexDigit(s[i], v)
          then
            digits := digits + s[i]
          else
            exit ;
  Result := true ;
end ;

function HexTextToBytes(const s : string ; out bytes : TBytes) : boolean ;
var
  t : string ;
  i, hi, lo : integer ;
begin
  Result := false ;
  bytes := nil ;
  if not CleanHex(s, t) or (t = '') or Odd(Length(t))
    then
      exit ;
  SetLength(bytes, Length(t) div 2) ;
  for i := 0 to Length(bytes) - 1 do
    begin
      HexDigit(t[2*i + 1], hi) ;
      HexDigit(t[2*i + 2], lo) ;
      bytes[i] := hi * 16 + lo ;
    end ;
  Result := true ;
end ;

function BytesToHexText(data : PByte ; count : integer) : string ;
var
  i : integer ;
  sb : TStringBuilder ;
begin
  sb := TStringBuilder.Create(count * 3) ;
  try
    for i := 0 to count - 1 do
      begin
        if i > 0
          then
            if (i mod 16) = 0
              then
                sb.Append(LineEnding)
              else
                sb.Append(' ') ;
        sb.Append(IntToHex(data[i], 2)) ;
      end ;
    Result := sb.ToString ;
  finally
    sb.Free ;
  end ;
end ;

function ParsePattern(var spec : TSearchSpec) : string ;
var
  words  : TStringList ;
  digits : string ;
  i, v   : integer ;
begin
  Result := '' ;
  spec.Pattern := nil ;
  case spec.Kind of
    skHexBytes :
      begin
        if not HexTextToBytes(spec.Text, spec.Pattern)
          then
            exit('Enter hex bytes, e.g. A9 00 85 F1') ;
        if Length(spec.Pattern) > MaxHexBytes
          then
            exit(Format('At most %d hex bytes', [MaxHexBytes])) ;
      end ;
    skHexWords :
      begin
        words := TStringList.Create ;
        try
          { blanks/commas separate words; without separators chunks of 4 }
          ExtractStrings([' ', ',', #9], [], PChar(spec.Text), words) ;
          if (words.Count = 1) and (Length(words[0]) > 4)
            then
              begin
                if not CleanHex(words[0], digits) or
                   ((Length(digits) mod 4) <> 0)
                  then
                    exit('Enter hex words of 4 digits, e.g. FFFA 1C00') ;
                words.Clear ;
                i := 1 ;
                while i <= Length(digits) do
                  begin
                    words.Add(Copy(digits, i, 4)) ;
                    inc(i, 4) ;
                  end ;
              end ;
          if words.Count = 0
            then
              exit('Enter hex words, e.g. FFFA 1C00') ;
          if words.Count > MaxHexWords
            then
              exit(Format('At most %d hex words', [MaxHexWords])) ;
          SetLength(spec.Pattern, 2 * words.Count) ;
          for i := 0 to words.Count - 1 do
            begin
              if not ParseHex(words[i], v) or (v > $FFFF)
                then
                  exit('Invalid hex word: ' + words[i]) ;
              spec.Pattern[2*i]     := v and $FF ;   { low byte first }
              spec.Pattern[2*i + 1] := v shr 8 ;
            end ;
        finally
          words.Free ;
        end ;
      end ;
    skText :
      begin
        if spec.Text = ''
          then
            exit('Enter the text to search for') ;
        if Length(spec.Text) > MaxTextChars
          then
            exit(Format('At most %d characters', [MaxTextChars])) ;
        SetLength(spec.Pattern, Length(spec.Text)) ;
        Move(spec.Text[1], spec.Pattern[0], Length(spec.Text)) ;
      end ;
  end ;
end ;

function NormByte(b : byte ; const spec : TSearchSpec) : byte ; inline ;
begin
  Result := b ;
  if spec.Kind <> skText
    then
      exit ;
  if spec.IgnoreBit7
    then
      Result := Result and $7F ;
  if not spec.CaseSensitive and (Result >= ord('a')) and (Result <= ord('z'))
    then
      Result := Result - 32 ;
end ;

function MatchAt(data : PByte ; const pat : TBytes ; const spec : TSearchSpec ;
                 at : integer) : boolean ;
var
  i : integer ;
begin
  for i := 0 to Length(pat) - 1 do
    if NormByte(data[at + i], spec) <> pat[i]
      then
        exit(false) ;
  Result := true ;
end ;

function SearchData(data : PByte ; const spec : TSearchSpec ;
                    from : integer ; out wrapped : boolean) : integer ;
var
  pat     : TBytes ;
  i, last,
  lo, pass : integer ;
begin
  Result := -1 ;
  wrapped := false ;
  if Length(spec.Pattern) = 0
    then
      exit ;
  SetLength(pat, Length(spec.Pattern)) ;
  for i := 0 to Length(pat) - 1 do
    pat[i] := NormByte(spec.Pattern[i], spec) ;
  lo := spec.RangeStart ;
  last := spec.RangeEnd - Length(pat) + 1 ;   { last possible match }
  if last < lo
    then
      exit ;
  for pass := 1 to 2 do
    begin
      if not spec.Backward
        then
          begin
            if from < lo then from := lo ;
            for i := from to last do
              if MatchAt(data, pat, spec, i)
                then
                  exit(i) ;
            from := lo ;
          end
        else
          begin
            if from > last then from := last ;
            for i := from downto lo do
              if MatchAt(data, pat, spec, i)
                then
                  exit(i) ;
            from := last ;
          end ;
      if not spec.Wrap
        then
          exit ;
      wrapped := true ;
    end ;
  wrapped := false ;
end ;

function Checksum16(data : PByte ; count : integer) : word ;
var
  i : integer ;
  sum : longword ;
begin
  sum := 0 ;
  for i := 0 to count - 1 do
    sum := sum + data[i] ;
  Result := sum and $FFFF ;
end ;

var
  CRCTable : array[0..255] of longword ;
  CRCTableDone : boolean = false ;

procedure MakeCRCTable ;
var
  n, k : integer ;
  c : longword ;
begin
  for n := 0 to 255 do
    begin
      c := n ;
      for k := 0 to 7 do
        if (c and 1) <> 0
          then
            c := $EDB88320 xor (c shr 1)
          else
            c := c shr 1 ;
      CRCTable[n] := c ;
    end ;
  CRCTableDone := true ;
end ;

function CRC32(data : PByte ; count : integer) : longword ;
var
  i : integer ;
  c : longword ;
begin
  if not CRCTableDone
    then
      MakeCRCTable ;
  c := $FFFFFFFF ;
  for i := 0 to count - 1 do
    c := CRCTable[(c xor data[i]) and $FF] xor (c shr 8) ;
  Result := c xor $FFFFFFFF ;
end ;

end.
