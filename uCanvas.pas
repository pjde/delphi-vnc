unit uCanvas;

(* Generic off-screen drawing canvas *)
(* 2016 pjde *)

{$mode objfpc}
{$H+}

interface

uses
  Classes, SysUtils, FrameBuffer, uFontInfo, Ultibo, freetypeh;

type
{ TCanvas }

  TCanvas = class
  private
    function GetFont (byFont : string; Load : boolean) : TFontInfo;
  public
    ColourFormat : LongWord;
    Width, Height : integer;
    Buffer : PByteArray;
    BufferSize : integer;
    BitCount : integer;
    Fonts : TList;
    procedure FindFonts;
    procedure SetSize (w, h : integer; cf : LongWord);
    procedure Fill (Col : LongWord); overload;
    procedure Fill (Rect : Ultibo.TRect; Col : LongWord); overload;
    function SetRect (Left, Top, Right, Bottom : long) : Ultibo.TRect;
    function TextExtents (Text, Font : string; Size : integer) : FT_Vector;
    function ScanLine (no : integer) : pointer;
    procedure DrawText (x, y : integer; Text, Font : string; FontSize : integer; Col : LongWord); overload;
    procedure DrawText (x, y : integer; Text, Font : string; FontSize : integer; Col : LongWord; Alpha : byte); overload;
    procedure Flush (FrameBuff : PFrameBufferDevice; x, y : integer);
    procedure Copy (FrameBuff : PFrameBufferDevice; x, y : integer);
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses GlobalConst, uLog;

var
  FTLib : PFT_Library;                // handle to FreeType library

function FT_New_Memory_Face (alibrary: PFT_Library; file_base: pointer; file_size: longint; face_index: integer; var face: PFT_Face) : integer; cdecl; external freetypedll Name 'FT_New_Memory_Face';

const
  DPI                           = 72;

function GetRValue (c : LongWord) : byte; inline;
begin
  Result := (c and $ff0000) shr 16;
end;

function GetGValue (c : LongWord) : byte; inline;
begin
  Result :=  (c and $ff00) shr 8;
end;

function GetBValue (c : LongWord) : byte; inline;
begin
  Result := c and $ff;
end;

function rgb (r, g, b : byte) : LongWord; inline;
begin
  Result := $ff000000 + (r shl 16) + (g shl 8) + b;
end;

{ TCanvas }
function TCanvas.SetRect (Left, Top, Right, Bottom : long) : Ultibo.TRect;
begin
  Result.left := Left;
  Result.top := Top;
  Result.right := Right;
  Result.bottom := Bottom;
end;

function TCanvas.TextExtents (Text, Font : string; Size : integer) : FT_Vector;
var
  err : integer;
  aFace : PFT_Face;
  fn : string;
  i: integer;
  kerning : boolean;
  glyph_index,
  prev : cardinal;
  delta : FT_Vector;
  anInfo : TFontInfo;
begin
  Result.x := 0;
  Result.y := 0;
  delta.x := 0;
  delta.y := 0;
  if not Assigned (FTLib) then exit;
  aFace := nil;
  if ExtractFileExt (Font) = '' then
    fn := Font + '.ttf'
  else
    fn := Font;
  anInfo := GetFont (fn, true);
  if anInfo = nil then exit;
  err := FT_New_Memory_Face (FTLIB, anInfo.Stream.Memory, anInfo.Stream.Size, 0, aFace);
  if err = 0 then  // if font face loaded ok
    begin
      err := FT_Set_Char_Size (aFace,                   // handle to face object
             0,                                         // char width in 1/64th of points - Same as height
             Size * 64,                                 // char height in 1/64th of points
             DPI,                                       // horizontal device resolution
             0);                                        // vertical device resolution
      if err = 0 then
        begin
          prev := 0;    // no previous char
          kerning := FT_HAS_KERNING (aFace);
          for i := 1 to length (Text) do
            begin                                       // convert character code to glyph index
              glyph_index := FT_Get_Char_Index (aFace, cardinal (Text[i]));
              if kerning and (prev <> 0) and (glyph_index <> 0) then
                begin
                  FT_Get_Kerning (aFace, prev, glyph_index, FT_KERNING_DEFAULT, &delta);
                  Result.x := Result.x + delta.x;
                  //if aFace^.glyph^.bitmap^.height + aFace^.glyph^.bitmap_top > Result.y then
                    //Result.y := aFace^.glyph^.bitmap^.height + aFace^.glyph^.bitmap_top;
                end;
               // load glyph image into the slot (erase previous one)
               err := FT_Load_Glyph (aFace, glyph_index, FT_LOAD_NO_BITMAP);
               if err > 0 then continue;                // ignore errors
               Result.x := Result.x + aFace^.glyph^.advance.x;
               //if aFace^.glyph^.bitmap^.height + aFace^.glyph^.bitmap_top > Result.y then
                 //Result.y := aFace^.glyph^.bitmap^.height + aFace^.glyph^.bitmap_top;
               prev := glyph_index;
            end;
        end;
      FT_Done_Face (aFace);
    end;
  Result.x := Result.x div 64;
  Result.y := Result.y div 64;
end;

function TCanvas.ScanLine (no : integer) : pointer;
begin
  cardinal (Result) := cardinal (Buffer) + (no * Width * 4);
end;

procedure TCanvas.DrawText (x, y : integer; Text, Font : string; FontSize : integer; Col : LongWord; Alpha : byte);
var
  err : integer;
  aFace : PFT_Face;
  fn : string;
  i, tx, ty : integer;
  kerning : boolean;
  glyph_index,
  prev : cardinal;
  delta : FT_Vector;
  anInfo : TFontInfo;

  procedure DrawChar (b : FT_Bitmap; dx, dy : integer);
  var
    i , j : integer;
    x_max, y_max : integer;
    p, q : integer;
    fm : PByte;
    rd, gn, bl : byte;
    cp : PCardinal; // canvas pointer
   begin
    x_max := dx + b.width;
    y_max := dy + b.rows;
//    Log ('dx ' + InttoStr (dx) + ' dy ' +  IntToStr (dy) + ' x max ' +  IntToStr (x_max) + ' y max ' + IntToStr (y_max));
    case ColourFormat of
      COLOR_FORMAT_ARGB32 : {32 bits per pixel Red/Green/Blue/Alpha (RGBA8888)}
        begin
          q := 0;
          for j := dy to y_max - 1 do
            begin
              if (j >= 0) and (j < Height) then
                begin
                  {$warnings off}
                  cp := PCardinal (LongWord (Buffer) + ((j * Width) + dx) * 4);
                  {$warnings on}
                  p := 0;
                  for i := dx to x_max - 1 do
                    begin
                      if (i >= 0) and (i < Width) then
                        begin
                          LongWord (fm) := LongWord (b.buffer) + q * b.width + p; // read alpha value of font char
                          fm^ := (fm^ * alpha) div 255;
                          rd := ((GetRValue (Col) * fm^) + (GetRValue (cp^) * (255 - fm^))) div 255;
                          gn := ((GetGValue (Col) * fm^) + (GetGValue (cp^) * (255 - fm^))) div 255;
                          bl := ((GetBValue (Col) * fm^) + (GetBValue (cp^) * (255 - fm^))) div 255;
                          cp^ := rgb (rd, gn, bl);
                        end;
                      p := p + 1;
                      Inc (cp, 1);
                    end;
                  q := q + 1;
                end;
            end;
        end; // colour format
      end; // case
  end;

begin
  if not Assigned (FTLib) then exit;
  aFace := nil;
  tx := x;
  ty := y;
  delta.x := 0;
  delta.y := 0;
  if ExtractFileExt (Font) = '' then
    fn := Font + '.ttf'
  else
    fn := Font;
  anInfo := GetFont (fn, true);
  if anInfo = nil then exit;
  err := FT_New_Memory_Face (FTLIB, anInfo.Stream.Memory, anInfo.Stream.Size, 0, aFace);
  if err = 0 then  // if font face loaded ok
    begin
      err := FT_Set_Char_Size (aFace,                   // handle to face object
             0,                                         // char_width in 1/64th of points - Same as height
             FontSize * 64,                             // char_height in 1/64th of points
             DPI,                                       // horizontal device resolution - dots per inch
             0);                                        // vertical device resolution - dots per inch
      if err = 0 then
        begin
          prev := 0;    // no previous char
          kerning := FT_HAS_KERNING (aFace);
          for i := 1 to length (Text) do
            begin                                       // convert character code to glyph index
              glyph_index := FT_Get_Char_Index (aFace, cardinal (Text[i]));
              if kerning and (prev <> 0) and (glyph_index <> 0) then
                begin
                  FT_Get_Kerning (aFace, prev, glyph_index, FT_KERNING_DEFAULT, &delta);
                  tx := tx + delta.x div 64;
                end;
               // load glyph image into the slot (erase previous one)
               err := FT_Load_Glyph (aFace, glyph_index, FT_LOAD_RENDER);
               if err > 0 then continue;                // ignore errors
               // now draw to our target surface
               DrawChar (aFace^.glyph^.bitmap, tx + aFace^.glyph^.bitmap_left,
                          ty - aFace^.glyph^.bitmap_top);
               tx := tx + aFace^.glyph^.advance.x div 64;
               prev := glyph_index;
            end;
        end;
      FT_Done_Face (aFace);
    end;
end;

procedure TCanvas.DrawText (x, y : integer; Text, Font : string;
  FontSize : integer; Col : LongWord);
begin
  DrawText (x, y, text, Font, FontSize, Col, 255);
end;

function TCanvas.GetFont (byFont : string; Load : boolean) : TFontInfo;
var
  i : integer;
  f : TFilestream;
begin
  Result := nil;
  for i :=  0 to Fonts.Count - 1 do
    begin
      if TFontInfo (Fonts[i]).FileName = byFont then
        begin
          Result := TFontInfo (Fonts[i]);
          break;
        end;
    end;
  if (Result = nil) and FileExists (byFont) then
    begin
      Result := TFontInfo.Create;
      if FontInfo (byFont, Result) then
        Fonts.Add (Result)
      else
        begin
          Result.Free;
          Result := nil;
        end;
    end;
  if (Result = nil) or (not Load) then exit;
  if Result.Stream <> nil then exit;        // already loaded
  Result.Stream := TMemoryStream.Create;
  try
    f := TFileStream.Create (byFont, fmOpenRead);
    Result.Stream.CopyFrom (f, f.Size);
    f.Free;
  except
 //   Log ('Error loading font.');
    Result.Stream.Free;
    Result.Stream := nil;
    end;
end;

procedure TCanvas.FindFonts;
var
  i : integer;
  SearchRec : TSearchRec;
  anInfo : TFontInfo;
begin
  for i := 0 to Fonts.Count - 1 do   // first clear list
    TFontInfo (Fonts[i]).Free;
  Fonts.Clear;
  if FindFirst ('C:\*.ttf', faAnyFile, SearchRec) = 0 then
    repeat
      anInfo := TFontInfo.Create;
      if FontInfo (SearchRec.Name, anInfo) then
        Fonts.Add (anInfo)
      else
        anInfo.Free;
    until FindNext (SearchRec) <> 0;
  FindClose (SearchRec);
end;

procedure TCanvas.SetSize (w, h : integer; cf : LongWord);
var
  bc : integer;
begin
  if Buffer <> nil then FreeMem (Buffer);
  Buffer := nil;
  Width := w;
  Height := h;
  ColourFormat := cf;
  case ColourFormat of
    COLOR_FORMAT_ARGB32, {32 bits per pixel Alpha/Red/Green/Blue (ARGB8888)}
    COLOR_FORMAT_ABGR32, {32 bits per pixel Alpha/Blue/Green/Red (ABGR8888)}
    COLOR_FORMAT_RGBA32, {32 bits per pixel Red/Green/Blue/Alpha (RGBA8888)}
    COLOR_FORMAT_BGRA32 : bc := 4; {32 bits per pixel Blue/Green/Red/Alpha (BGRA8888)}
    COLOR_FORMAT_RGB24, {24 bits per pixel Red/Green/Blue (RGB888)}
    COLOR_FORMAT_BGR24  : bc := 3; {24 bits per pixel Blue/Green/Red (BGR888)}
    // COLOR_FORMAT_RGB18  = 6; {18 bits per pixel Red/Green/Blue (RGB666)}
    COLOR_FORMAT_RGB16, {16 bits per pixel Red/Green/Blue (RGB565)}
    COLOR_FORMAT_RGB15  : bc := 2; {15 bits per pixel Red/Green/Blue (RGB555)}
    COLOR_FORMAT_RGB8   : bc := 1; {8 bits per pixel Red/Green/Blue (RGB332)}
    else bc := 0;
    end;
  BufferSize := Width * Height * bc;
  if BufferSize > 0 then
    begin
      GetMem (Buffer, BufferSize);
      FillChar (Buffer^, BufferSize, 0);
    end;
end;

procedure TCanvas.Fill (Col : LongWord);
var
  Rect : Ultibo.TRect;
begin
  Rect := SetRect (0, 0, Width - 1, Height - 1);
  Fill (Rect, Col);
end;

procedure TCanvas.Fill (Rect : Ultibo.TRect; Col : LongWord);
var
  i, j : integer;
  p : pointer;
begin
  case ColourFormat of
    COLOR_FORMAT_ARGB32 : {32 bits per pixel Red/Green/Blue/Alpha (RGBA8888)}
      begin
//        Log ('Fill Width ' + IntToStr (Rect.right - rect.left) + ' Height '
//        + IntToStr (Rect.bottom - rect.top));
        if Rect.left < 0 then Rect.left:= 0;
        if Rect.top < 0 then rect.top := 0;
        if Rect.left >= Width then exit;
        if Rect.top >= Height then exit;
        if Rect.right >= Width then Rect.right := width - 1;
        if Rect.bottom >= Height then Rect.bottom := height - 1;
        if Rect.left >= Rect.right then exit;
        if Rect.top >= Rect.bottom then exit;
        for j := Rect.top to Rect.bottom do
          begin
            cardinal (p) := cardinal (Buffer) + ((j * Width) + Rect.left) * 4;
            for i := Rect.left to Rect.right do
              begin       // 000000ff blue   0000ff00 green    00ff0000 red
                PCardinal (p)^ := Col;
                Inc (p, 4);
              end;
          end;
      end;
    end;
end;

procedure TCanvas.Flush (FrameBuff : PFrameBufferDevice; x, y : integer);
begin
  FramebufferDevicePutRect (FrameBuff, x, y, Buffer, Width, Height, 0, FRAMEBUFFER_TRANSFER_DMA);
end;

procedure TCanvas.Copy (FrameBuff : PFrameBufferDevice; x, y : integer);
begin
  FramebufferDeviceGetRect (FrameBuff, x, y, Buffer, Width, Height, 0, FRAMEBUFFER_TRANSFER_DMA);
end;

constructor TCanvas.Create;
var
  res : integer;
begin
  Width := 0;
  Height := 0;
  Buffer := nil;
  ColourFormat := COLOR_FORMAT_UNKNOWN;
  Fonts := TList.Create;
  if FTLib = nil then
    begin
      res := FT_Init_FreeType (FTLib);
      if res <> 0 then Log ('FTLib failed to Initialise.');
    end;
end;

destructor TCanvas.Destroy;
var
  i : integer;
begin
  for i := 0 to Fonts.Count - 1 do TFontInfo (Fonts[i]).Free;
  Fonts.Free;
  if Buffer <> nil then FreeMem (Buffer);
  inherited;
end;

end.

