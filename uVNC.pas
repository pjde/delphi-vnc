unit uVNC;

{$mode objfpc}{$H+}
{hints off}
{$pointermath on}

{ VNC Server (c) 2021 PJde }
{ LGPLv2.1 with static linking exception }

interface

uses
  Classes, SysUtils, FrameBuffer, WinSock2, uCanvas, SyncObjs, uZLib;

const
  ft : array[boolean] of string = ('false', 'true');

  siOffline                        = 1;  // socket is offline
  siConnected                      = 2;  // socket has connected
  siProtocol                       = 3;  // socket deciding protocol
  siAuthenticate                   = 4;  // socket deciding authentication
  siSecurity                       = 8;  // socket deciding security
  siOnline                         = 5;  // socket communicating
  siClientInit                     = 6;
  siServerInit                     = 7;

  rfbConnFailed                    = 0;
  rfbNoAuth                        = 1;
  rfbVncAuth                       = 2;

  rfbVncAuthOK                     = 0;
  rfbVncAuthFailed                 = 1;
  rfbVncAuthTooMany                = 2;

  rfbFramebufferUpdate             = 0;
  rfbSetColourMapEntries           = 1;
  (* server -> client *)
  rfbBell                          = 2;
  rfbServerCutText                 = 3;
  (* client -> server *)
  rfbSetPixelFormat                = 0;
  rfbFixColourMapEntries           = 1; (* not currently supported *)
  rfbSetEncodings                  = 2;
  rfbFramebufferUpdateRequest      = 3;
  rfbKeyEvent                      = 4;
  rfbPointerEvent                  = 5;
  rfbClientCutText                 = 6;

  // encoding types   https://www.iana.org/assignments/rfb/rfb.xhtml
  rfbEncodingRaw                   = 0;
  rfbEncodingCopyRect              = 1;
  rfbEncodingRRE                   = 2;
  rfbEncodingCoRRE                 = 4;   // obsolete
  rfbEncodingHextile               = 5;
  rfbEncodingZLib                  = 6;
  rfbEncodingTight                 = 7;
  rfbEncodingZLibHex               = 8;
  rfbEncodingUltra                 = 9;
  rfbEncodingTRLE                  = 15;
  rfbEncodingZRLE                  = 16;
  rfbEncodingZYWRLE                = 17;
  rfbEncodingH264                  = 20;
  rfbEncodingJPEG                  = 21;
  rfbEncodingJRLE                  = 22;
  rfbEncodingVAH264                = 23;
  rfbEncodingZRLE2                 = 24;
  rfbEncodingCursor                = -239;  // pseudo
  rfbEncodingDesktopSize           = -223;  // pseudo

  rfbHextileRaw	                   = 1 shl 0;
  rfbHextileBackgroundSpecified	   = 1 shl 1;
  rfbHextileForegroundSpecified	   = 1 shl 2;
  rfbHextileAnySubrects	           = 1 shl 3;
  rfbHextileSubrectsColoured       = 1 shl 4;

type
  TVNCThread = class;

  TCard8 = byte;          // 8 bit cardinal
  PCard8 = ^TCard8;
  TCard16 = word;         // 16 bit cardinal
  PCard16 = ^TCard16;
  TCard32 = Cardinal;     // 32 bit cardinal
  PCard32 = ^TCard32;

  TTable8 = array [word] of TCard8;
  TTable16 = array [word] of TCard16;
  TTable32 = array [word] of TCard32;

  PTable8 = ^TTable8;
  PTable16 = ^TTable16;
  PTable32 = ^TTable32;

  TVNCPointerEvent = procedure (Sender : TObject; Thread : TVNCThread; x, y : TCard16; BtnMask : TCard8);
  TVNCKeyEvent = procedure (Sender : TObject; Thread : TVNCThread; Key : TCard32; Down : boolean);
  TVNCDrawEvent = procedure (Sender : TObject; Canvas : TCanvas; x, y, h, w : cardinal);
  TVNCRectEvent = procedure (Sender : TObject; r : TRect);
  TVNCSizeEvent = procedure (sender : TObject; var x, y : integer);

  TRectangle = record
    x, y : TCard16;
    w, h : TCard16;
  end;

  TFramebufferUpdateRectHeader = record
    r : TRectangle;
    encoding : TCard32;
  end;

  PFramebufferUpdateRectHeader = ^TFramebufferUpdateRectHeader;

  TPixelFormat = record
    BitsPerPixel : TCard8;
    Depth : TCard8;
    BigEndian : Boolean;
    TrueColour : Boolean;
    RedMax : TCard16;
    GreenMax : TCard16;
    BlueMax : TCard16;
    RedShift : TCard8;
    GreenShift : TCard8;
    BlueShift : TCard8;
  end;
  PPixelFormat = ^TPixelFormat;

  TTransFunc = procedure (Table : Pointer; InFormat, OutFormat : TPixelFormat;
                                iptr, optr : PByte;  BytesBetweenInputLines,  Width, Height : integer);

  TClientInitMsg = record
    shared : TCard8;
  end;

  TServerInitMsg = record
    FrameBufferWidth : TCard16;
    FrameBufferHeight : TCard16;
    PixFormat : TPixelFormat;
    NameLength : TCard32;
    (* followed by char name[nameLength] *)
  end;

  rfbCopyRect = record
    srcX,srcY : TCard16;
  end;

  rfbRREHeader = record
    nSubrects : TCard32;
  end;

  TFramebufferUpdateMsg = record
   msgType : TCard8; (* always rfbFramebufferUpdate *)
   pad : TCard8;
   nRects : TCard16;
  (* followed by nRects rectangles *)
  end;

  TSetPixelFormatMsg = record
    msgType : TCard8; (* always rfbSetPixelFormat *)
    pad1 : TCard8;
    pad2: TCard16;
    pixFormat : TPixelFormat;
    end;

  TFramebufferUpdateRequestMsg = record
    msgType : TCard8; (* always rfbFramebufferUpdateRequest *)
    incremental : TCard8;
    x : TCard16;
    y : TCard16;
    w : TCard16;
    h : TCard16;
  end;

  TPointerEventMsg = record
    msgType : TCard8; (* always rfbPointerEvent *)
    buttonMask: TCard8; (* bits 0-7 are buttons 1-8, 0=up, 1=down *)
    x : TCard16;
    y : TCard16;
  end;

  TKeyEventMsg = record
    msgType : TCard8; (* always rfbKeyEvent *)
    down : TCard8; (* true if down (press), false if up *)
    pad : TCard16;
    key : TCard32; (* key is specified as an X keysym *)
  end;

const
  SRectangle = SizeOf (TRectangle);
  SFramebufferUpdateRectHeader = SizeOf (TFrameBufferUpdateRectHeader);

function Display (a : string): string;
function DisplayS (a : TStream): string;
function EncoderName (aType : integer) : string;

function Card8 (a : string; Index : integer) : TCard8;
function Card16 (a : string; Index : integer) : TCard16;
function Card32 (a : string; Index : integer) : TCard32;

function Str16 (Value : integer) : string;
function Str32 (Value : cardinal) : string;
function Str8 (Value : integer) : string;

function Swap16IfLE (s : TCard16) : TCard16;
function Swap32IfLE (l : TCard32) : TCard32;

function Swap16 (Value : TCard16) : TCard16;
function Swap32 (Value : TCard32) : TCard32;

type
  TVNCServer = class;

  { TVNCThread }
  TVNCThread = class (TWinsock2TCPServerThread)
    FOwner : TVNCServer;
    RxBuff : string;
    State : integer;
    RxID, RxLen : Word;
    RxUnitID : byte;
    FCanTRLE, FCanZRLE,
    FCanHextile, FCanResize : boolean;
    Prefered : integer;
  public
    Shared : boolean;
    VMajor, VMinor : integer;
    PixelFormat : TPixelFormat;
    Stream : TMemoryStream;
    Rects : array of TRect;
    Back : TCard32;
    BackValid : boolean;
    Event : TEvent;
    count : integer;
    z : TZStreamRec;
    FirstUpdate : boolean;
    function TestColours (aRect : TRect; var bg : TCard32) : boolean;
    function EncodeRect (aRect : TRect) : boolean; // this maybe same as Rects size or a subrectangle if Rects is large
    function CompressStream (InStream, OutStream : TStream): integer;
    procedure SendFrame;
    procedure Send (s : string);
  public
    constructor Create (aServer : TWinsock2TCPServer);
    destructor Destroy; override;
  end;

  { TVNCServer }
  TVNCServer = class (TWinsock2TCPListener)
  private
    FOnKey : TVNCKeyEvent;
    FOnPointer: TVNCPointerEvent;
    FOnGetRect : TVNCRectEvent;
    FOnGetSize : TVNCSizeEvent;
    Height, Width : LongWord;
    VerMajor, VerMinor : integer;
    procedure DoCreateThread (aServer : TWinsock2TCPServer; var aThread : TWinsock2TCPServerThread);
  protected
    procedure DoConnect (aThread : TWinsock2TCPServerThread); override;
    procedure DoDisconnect (aThread : TWinsock2TCPServerThread); override;
    function DoExecute (aThread : TWinsock2TCPServerThread) : Boolean; override;
  public
    Title : string;
    Canvas : TCanvas;
    procedure InitCanvas;
    constructor Create;
    destructor Destroy; override;
    property OnPointer : TVNCPointerEvent read FOnPointer write FOnPointer;
    property OnKey : TVNCKeyEvent read FOnKey write FOnKey;
    property OnGetRect : TVNCRectEvent read FOnGetRect write FOnGetRect;
    property OnGetSize : TVNCSizeEvent read FonGetSize write FOnGetSize;
  end;


implementation

uses uLog, GlobalConst, Platform;

procedure Add8 (aStream : TStream; aByte : TCard8); inline;
begin
  aStream.Write (aByte, 1);
end;

procedure Add16 (aStream : TStream; aWord : TCard16); inline;
var
  bWord : TCard16;
begin
  bWord := Swap16 (aWord);
  aStream.Write (bWord, 2);
end;

procedure Add32 (aStream : TStream; aDWord : TCard32); inline;
var
  bDWord : TCard32;
begin
  bDWord := Swap32 (aDWord);
  aStream.Write (bDWord, 4);
end;

procedure AddPix (aStream : TStream; aPix : TCard32);  // translator added here
begin
  aStream.Write (aPix, 4);
end;

{ TVNCResponse }
function TVNCThread.TestColours (aRect : TRect; var bg : TCard32) : boolean;
var           // this checks if all poxels in rect are the same colour
  i, j : integer;
  first : boolean;
  aRow : PTable32;
begin
  first := true;
  Result := true;
  if FOwner = nil then exit;
  if not Assigned (FOwner.Canvas) then exit;
  for j := aRect.Top to aRect.Top + aRect.Bottom - 1 do
    begin
      aRow := FOwner.Canvas.ScanLine (j);   // need to make this thread safe
      for i := aRect.Left to aRect.Left + aRect.Right - 1 do
        begin
          if first then bg := aRow^[i];
          first := false;
          if aRow^[i] = bg then continue;
          Result := false;
          exit;
        end;
    end;
end;

(*  No. of bytes Type [Value] Description
    1 U8 0 message-type
    1 padding
    2 U16 number-of-rectangles
        This is followed by number-of-rectangles rectangles of pixel data. Each rectangle
        consists of:
    No. of bytes Type [Value] Description
    2 U16 x-position
    2 U16 y-position
    2 U16 width
    2 U16 height
    4 S32 encoding-type     *)

function TVNCThread.EncodeRect (aRect : TRect) : boolean;
const
  bufferSize = 32768;
var
  i, j : integer;
  w, h : TCard16;
  x, y : TCard16;
  xRect : TRect;
  bg : TCard32;
  aRow : PTable32;
  m : Int64;
  zi : TMemoryStream;
begin
  Result := false;
  if FOwner = nil then exit;
  if not Assigned (FOwner.Canvas) then exit;
//  Log ('Encoding Rect ' + aRect.Width.tostring + ' by ' + aRect.Height.ToString + ' @ ' + aRect.Left.ToString + ',' + aRect.Top.ToString);
  Add16 (Stream, aRect.Left);         //  X - Position
  Add16 (Stream, aRect.Top);          //  Y - Position
  Add16 (Stream, aRect.Right);        //  Width
  Add16 (Stream, aRect.Bottom);       //  Height

  case Prefered of
    rfbEncodingRaw :
      begin
        Add32 (Stream, rfbEncodingRaw); // raw encoding
        for j := aRect.Top to  aRect.Top + aRect.Bottom - 1 do
           begin
            aRow := FOwner.Canvas.ScanLine(j);  // need to make this thread safe
            for i := aRect.Left to aRect.Left + aRect.Right - 1 do
              AddPix (Stream, aRow^[i]);    // needs translation
           end;
      end;
    rfbEncodingHextile :
      begin
        Add32 (Stream, rfbEncodingHextile); // hextile encoding
        y := aRect.Top;
        while y < aRect.Top + aRect.Bottom do
          begin
            if y + 16 < aRect.Top + aRect.Bottom then
              h := 16
            else
              h := aRect.Top + aRect.Bottom - y;
            x := aRect.Left;
            while x < aRect.Left + aRect.Right do
              begin
                if x + 16 < aRect.Left + aRect.Right then
                  w := 16
                else
                  w := aRect.Left + aRect.Right - x;
                xRect := Rect (x, y, w, h);
                if TestColours (xRect, bg) then
                  begin
                    if (bg <> back) or (not BackValid) then
                      begin
                        back := bg;
                        BackValid := true;
                        // this is encoded with new back colour
                        Add8 (Stream, rfbHextileBackgroundSpecified);  // background
                        AddPix (Stream, back);  // background colour
                      end
                    else
                      begin
                        // this is encoded using existing back colour
                        Add8 (Stream, 0);   // no background specified
                      end;
                  end
                else
                  begin
                    // this is encoded as raw
                    BackValid := false;
                    Add8 (Stream, rfbHextileRaw);                 // raw encoded
                    for j := y to y + h - 1 do
                      begin
                        aRow := FOwner.Canvas.ScanLine(j);  // need to make this thread safe
                        for i := x to x + w - 1 do
                          AddPix (Stream, aRow^[i]);    // needs translation
                      end;
                  end;
                x := x + 16;
              end;  // while x
            y := y + 16;
          end;    // while y
      end; // hextile
    rfbEncodingZLib :
      begin
        Add32 (Stream, rfbEncodingZLib); // ZLib encoding
        i := aRect.Left;
        y := aRect.Top;
        if aRect.Left + aRect.Right <= FOwner.Width then
          w := aRect.Right
        else
          w := FOwner.Width - aRect.Left;
        if aRect.Top + aRect.Bottom <= FOwner.Height then
          h := aRect.Bottom
        else
          h := FOwner.Height - aRect.Top;
        zi := TMemoryStream.Create;
        for i := aRect.Top to aRect.Top + h - 1 do
          begin
            aRow := FOwner.Canvas.ScanLine (i);  // need to make this thread safe
            zi.Write (aRow^[aRect.Left], w * 4);
          end;
        m := Stream.Position;
        Add32 (Stream, 0);                     // place holder for size
        zi.Seek (0, soFromBeginning);
        CompressStream (zi, Stream);
        Stream.Seek (m, soFromBeginning);
        Add32 (Stream, Stream.Size - (m + 4));
        Stream.Seek (0, soFromEnd);
        zi.Free;
      end;
    end;   // case
  Result := true;
end;

function TVNCThread.CompressStream (InStream, OutStream : TStream) : integer;
{ adapted from zlibar.pas Copyright (C) 2005 Andrew Haines }
const
  MAX_IN_BUF_SIZE = 1024;
  MAX_OUT_BUF_SIZE = 1024;
var
  err : integer;
  input_buffer : array [0 .. MAX_IN_BUF_SIZE - 1] of byte;
  output_buffer : array [0 .. MAX_OUT_BUF_SIZE - 1] of byte;
begin
  Result := 0;
  FillChar (input_buffer, SizeOf (input_buffer), 0);
  if FirstUpdate then // need this as VNC uses a single zlib stream
    begin
      z.zalloc := nil;
      z.zfree := nil;
      z.opaque := nil;
	    err := deflateInit (z, Z_DEFAULT_COMPRESSION);
      FirstUpdate := false;
	  end;
  InStream.Position := 0;
  while InStream.Position < InStream.Size do
    begin
      z.next_in := @input_buffer;
      z.avail_in := InStream.Read (input_buffer, MAX_IN_BUF_SIZE);
      repeat
        z.next_out := @output_buffer;
        z.avail_out := MAX_OUT_BUF_SIZE;
        err := deflate (z, Z_SYNC_FLUSH);
        Result += OutStream.Write (output_buffer, MAX_OUT_BUF_SIZE - z.avail_out);
      until Z.avail_out > 0;
    end;
end;

procedure TVNCThread.SendFrame;
var
  i : integer;
begin
  Stream.Clear;
  Add8 (Stream, 0);                 // Msg Type
  Add8 (Stream, 0);                 // padding
  Add16 (Stream, length (Rects));   // nos rect
  for i := 0 to length (Rects) - 1 do EncodeRect (Rects[i]);
  Server.WriteData (Stream.Memory, Stream.Size);
end;

{ TVNCThread }
procedure TVNCThread.Send (s : string);
begin
  try
    Server.WriteData (@s[1], length (s));
  except
    end;
end;

constructor TVNCThread.Create (aServer : TWinsock2TCPServer);
begin
  inherited Create (aServer);
  RxBuff := '';
  Prefered := -1;
  Back := 0;
  BackValid := false;
  SetLength (Rects, 1);  // currently only have a single rect
  count := 0;
  FirstUpdate := true;
  FillChar (z, SizeOf (z), 0);
  Stream := TMemoryStream.Create;
end;

destructor TVNCThread.Destroy;
begin
  Stream.Free;
  inherited Destroy;
end;

{ TVNCServer }
procedure TVNCServer.DoCreateThread (aServer : TWinsock2TCPServer;
  var aThread : TWinsock2TCPServerThread);
begin
  aThread := TVNCThread.Create (aServer);
  with TVNCThread (aThread) do
    begin
      FOwner := Self;
      State := siOffline;
    end;
end;

procedure TVNCServer.DoConnect (aThread : TWinsock2TCPServerThread);
var
  aVNCThread : TVNCThread;
  tmp : string;
begin
  inherited DoConnect (aThread);
  aVNCThread := TVNCThread (aThread);
  Log ('Client Connected.');
  with aVNCThread do
    begin
      State := siProtocol;
      tmp := format ('RFB %.3d.%.3d'#10, [VerMajor, VerMinor]);
      try
        Server.WriteData (@tmp[1], length (tmp));
      except
        end;
    end;
end;

procedure TVNCServer.DoDisconnect (aThread : TWinsock2TCPServerThread);
var
  aVNCThread : TVNCThread;
begin
  aVNCThread := TVNCThread (aThread);
  if not aVNCThread.FirstUpdate then
    deflateEnd (aVNCThread.z);
  inherited DoDisconnect (aThread);
  Log ('Client Disconnected.');
end;

function TVNCServer.DoExecute (aThread : TWinsock2TCPServerThread) : Boolean;
var
  Pixs, tmp : string;
  i : integer;
  a, b : TCard16;
  x, y, w, h : TCard16;
  BtnMask : TCard8;
  aVNCThread : TVNCThread;
  KeyDown : boolean;
  Key : TCard32;
  closed, d, loop : boolean;
  c : integer;
  buff : array [0..255] of byte;
begin
  Result := inherited DoExecute (aThread);
  if not Result then exit;
  aVNCThread := TVNCThread (aThread);
  c := 256;
  closed := false;
  d := aThread.Server.ReadAvailable (@buff[0], 255, c, closed);
  if closed or not d then Result := false;
  if (c = 0) or closed then exit;
//  Log ('Read ' + inttostr (c) + ' bytes.');
  with aVNCThread do
    begin
      i := Length (RxBuff);
      Setlength (RxBuff, i + c);
      Move (buff[0], RxBuff[i + 1], c);
      loop := true;
      while loop do
        case State of
          siProtocol :
            begin
              if (Length (RxBuff) >= 12) then
                begin
                  if Copy (RxBuff, 1, 3) = 'RFB' then
                    begin
                      VMajor := StrToIntDef (Copy (RxBuff, 5, 3), 0);
                      VMinor := StrToIntDef (Copy (RxBuff, 9, 3), 0);
                      Log (format ('Using Version %d.%d.', [VMajor, VMinor]));
                      if VMajor = 3 then
                        begin
                          if VMinor = 8 then // 3.8
                            begin
                              State := siSecurity;
                              Send (#1#1); // 1 security - none
                            end
                          else if VMinor = 3 then // 3.3
                            begin
                              State := siAuthenticate;
                              Send (#0#0#0#1);
                            end
                          else
                            begin // bad version
                              Result := false;
                              exit;
                            end;
                        end
                      else
                        begin  // bad version
                          Result := false;
                          exit;
                        end;
                      RxBuff := Copy (RxBuff, 13);
                    end
                  else
                    begin
                      Log ('Protocol failed.');
                      Result := false;
                      exit;
                    end;
                end
              else
                Loop := false; // need more bytes
            end;
          siSecurity :
            begin
              if Length (RxBuff) >= 1 then
                begin
                  Log ('Security ' + IntToStr (ord (RxBuff[1])));
                  if RxBuff[1] = #1 then
                    begin
                      State := siAuthenticate;
                      Send (#0#0#0#0);  // SecurityResult Handshake 0 = OK
                    end
                  else
                    begin
                      Result := false;
                      exit;
                    end;
                  RxBuff := Copy (RxBuff, 2);
                end
              else
                Loop := false;
            end;
          siAuthenticate :
            begin
              if Length (RxBuff) >= 1 then
                begin
                  Shared := Copy (RxBuff, 1, 1) <> #0;
                  RxBuff := Copy (RxBuff, 2);
                  State := siConnected;
              (*  1 U8 bits-per-pixel
                  1 U8 depth
                  1 U8 big-endian-flag
                  1 U8 true-colour-flag
                  2 U16 red-max
                  2 U16 green-max
                  2 U16 blue-max
                  1 U8 red-shift
                  1 U8 green-shift
                  1 U8 blue-shift
                  3 padding   *)
                  Pixs := #32#24#0#1#0#255#0#255#0#255#16#8#0#0#0#0;
              (*  No. of bytes Type [Value] Description
                  2 U16 framebuffer-width
                  2 U16 framebuffer-height
                  16 PIXEL_FORMAT server-pixel-format
                  4 U32 name-length
                  name-length U8 array name-string  *)
                 // shdhh
                  tmp := Str16 (Width) +
                         Str16 (Height) +
                         Pixs +
                         Str32 (length (Title)) +
                         Title;
      //          Log (display (tmp));
                  Send (tmp);
                  RxBuff := Copy (RxBuff, 2);
                end
              else
                Loop := false;
            end;
          siConnected :
            begin
              if Length (RxBuff) >= 1 then
                case Card8 (RxBuff, 1) of
                   0 :
                      begin
                        Log ('Set Pixel Format');
                        if Length (RxBuff) >= 20 then
                          with PixelFormat do
                            begin
                              BitsPerPixel := Card8 (RxBuff, 5);
                              Depth := Card8 (RxBuff, 6);
                              BigEndian := Card8 (RxBuff, 7) <> 0;
                              TrueColour := Card8 (RxBuff, 8) <> 0;
                              RedMax := Card16 (RxBuff, 9);
                              GreenMax := Card16 (RxBuff, 11);
                              BlueMax := Card16 (RxBuff, 13);
                              RedShift := Card8 (RxBuff, 15);
                              GreenShift := Card8 (RxBuff, 16);
                              BlueShift := Card8 (RxBuff, 17);
                              Log ('  BitsPerPixel'#9': ' + IntToStr (BitsPerPixel));
                              Log ('  Depth       '#9': ' + IntToStr (Depth));
                              Log ('  Big Endian  '#9': ' + ft[BigEndian]);
                              Log ('  True Colour '#9': ' + ft[TrueColour]);
                              Log ('  Red Max     '#9': ' + IntToStr (RedMax));
                              Log ('  Green Max   '#9': ' + IntToStr (GreenMax));
                              Log ('  Blue Max    '#9': ' + IntToStr (BlueMax));
                              Log ('  Red Shift   '#9': ' + IntToStr (RedShift));
                              Log ('  Green Shift '#9': ' + IntToStr (GreenShift));
                              Log ('  Blue Shift  '#9': ' + IntToStr (BlueShift));
                              RxBuff := Copy (RxBuff, 21);
                            end   // with
                          else Loop := false;
                      end;
                    1 :
                      begin
                        Log ('Fix Color Map Entries.');
                        RxBuff := '';
                        Loop := false;
                      end;
                    2 :
                      begin
                        Log ('Set Encodings.');
                        if Length (RxBuff) >= 4 then
                          begin
                            a := card16 (RxBuff, 3);
                            Log ('  Nos encodings : ' + IntToStr (a));
                            if Length (RxBuff) >= 5 * a then
                              begin
                                for b := 1 to a do
                                  begin
                                    i := integer (card32 (RxBuff, 5 + ((b - 1) * 4)));
                                    Log ('  Encoding ' + IntToStr (b) + #9': ' + EncoderName (i));
                                    if i = rfbEncodingHextile then FCanHextile := true;
                                    if i = rfbEncodingDesktopSize then FCanResize := true;
                                    if (Prefered < 0) and (i in [rfbEncodingRaw, rfbEncodingHextile, rfbEncodingZlib]) then
                                       Prefered := i;
                                  end;
                                if Prefered < 0 then Prefered := rfbEncodingRaw;
                                Log ('Prefered Encoding ' + EncoderName (Prefered));
                                RxBuff := Copy (RxBuff, 5 + (4 * a));
                              end
                            else
                              Loop := false;
                          end
                        else
                          Loop := false;
                      end;
                    3 :
                      begin
               //       incremental := Card8 (RxBuff, 2);
                        x := Card16 (RxBuff, 3);
                        y := Card16 (RxBuff, 5);
                        w := Card16 (RxBuff, 7);
                        h := Card16 (RxBuff, 9);
                        if (w = Width) and (h = Height) then
                          begin
                            with Rects[0] do
                              begin
                                Left := x;
                                Top := y;
                                Right := w;
                                Bottom := h;
                              end;
                            RxBuff := Copy (RxBuff, 11);
                            if Assigned (FOnGetRect) then
                              FOnGetRect (aVNCThread, Rects[0])
                            else
                              Canvas.Copy (FramebufferDeviceGetDefault, 0, 0);
                            SendFrame;
                          end;
                    //    else
                      //    Log ('asked for smaller rect');

                    (*    if (w = Width) and (h = Height) then
                          a := 1
                        else
                          a := Length (Response.Rects) + 1;
                        SetLength (Response.Rects, a);
                        with Response.Rects[a - 1] do
                          begin
                            Left := x;
                            Top := y;
                            Right := w;
                            Bottom := h;
                          end;
   //                     Log ('Rects Pending'#9': ' + IntToStr (a));      *)
                    (*    RxBuff := Copy (RxBuff, 11);
                        if Assigned (FOnGetRect) then FonGetRect (aVNCThread, Response.Rects[0]);

                        Response.Event.SetEvent;          *)
                      end;
                    4 :   // key event
                      begin           // 8 bytes
                        if Length (RxBuff) >= 8 then
                          begin
                            KeyDown := Card8 (RxBuff, 2) = 1;
                            Key := Card32 (RxBuff, 5);
                            case Key of
                              $ff09 : Key := $09; // Tab
                              $ff08 : Key := $08; // BackSpace
                              $ff0d : Key := $0d; // Return
                              $ff1b : Key := $1b; // Escape
                          (*  $ff63 : Key := $00; // Insert
                              $ffff : Key := $00; // Delete
                              $ff50 : Key := $00; // Home
                              $ff57 : Key := $00; // End
                              $ff55 : Key := $00; // Page Up
                              $ff56 : Key := $00; // Page Down
                              $ff51 : Key := $00; // Left
                              $ff52 : Key := $00; // Up
                              $ff53 : Key := $00; // Right
                              $ff54 : Key := $00; // Down
                              $ffbe : Key := $00; // F1
                              $ffbf : Key := $00; // F2
                              $ffc0 : Key := $00; // F3
                              $ffc1 : Key := $00; // F4
                              $ffc2 : Key := $00; // F5
                              $ffc3 : Key := $00; // F6
                              $ffc4 : Key := $00; // F7
                              $ffc5 : Key := $00; // F8
                              $ffc6 : Key := $00; // F9
                              $ffc7 : Key := $00; // F10
                              $ffc8 : Key := $00; // F11
                              $ffc9 : Key := $00; // F12

                              Shift (left) 	0xffe1
                              Shift (right) 	0xffe2
                              Control (left) 	0xffe3
                              Control (right) 	0xffe4
                              Meta (left) 	0xffe7
                              Meta (right) 	0xffe8
                              Alt (left) 	0xffe9
                              Alt (right) 	0xffea        *)

                              else
                                begin
                                end;

                              end;
                            if Assigned (FOnKey) then FOnKey (Self, aVNCThread, Key, KeyDown);
                            RxBuff := Copy (RxBuff, 9);
                          end
                        else
                          Loop := false;
                      end;
                    5 :  // pointer event
                      begin          //  6 bytes long
                        if Length (RxBuff) >= 6 then
                          begin
                            BtnMask := Card8 (RxBuff, 2);
                            a := Card16 (RxBuff, 3);
                            b := Card16 (RxBuff, 5);
                            if Assigned (FOnPointer) then
                              FOnPointer (Self, aVNCThread, a, b, BtnMask)
                            else
                              CursorSetState (true, a, b, true);
                            RxBuff := Copy (RxBuff, 7);
                          end
                        else
                          Loop := false;
                      end;
                    6 :  // client cut text
                      begin   //  6 bytes long
                        if Length (RxBuff) >= 6 then
                          begin
                            Log ('Client Cut Text.');
                            a := Card32 (RxBuff, 3);
                            RxBuff := Copy (RxBuff, 9 + a);
                          end
                        else
                          Loop := false;
                      end;
                    else
                      begin
                        Log ('Garbage.');
                        RxBuff := '';
                        Loop := false;
                      end;
                  end      // case
               else
                 Loop := false;
            end;  // connected
        end;  // case / while
    end;
end;

procedure TVNCServer.InitCanvas;
begin
  if Assigned (FOnGetSize) then
    FOnGetSize (Self, Width, Height)
  else
    FramebufferGetPhysical (Width, Height);
  if Assigned (Canvas) then Canvas.Free;
  Canvas := TCanvas.Create;
  Canvas.SetSize (Width, Height, COLOR_FORMAT_ARGB32);
end;

constructor TVNCServer.Create;
begin
  inherited Create;
  BoundPort := 5900;
  OnCreateThread := @DoCreateThread;
  Width := 0;
  Height := 0;
  Canvas := nil;
  VerMajor := 3;
  VerMinor := 8;
end;

destructor TVNCServer.Destroy;
begin
  if Assigned (Canvas) then Canvas.Free;
  inherited Destroy;
end;

function Display (a : string) : string;
var
  i : integer;
begin
  Result := '';
  for i := 1 to length (a) do
    begin
      if CharInSet (a[i], [' ' .. '~']) then
        Result := Result + a[i]
      else
        Result := Result + '<' + IntToStr (ord (a[i])) + '>';
   end;
end;

function DisplayS (a : TStream) : string;
var
//  i : integer;
  b : Char;
  x : int64;
begin
  Result := '';
  b := #0;
  x := a.Position;
  a.Seek (0, soFromBeginning);
  while a.Position <> a.Size do
    begin
      a.read (b, 1);
//      if CharInSet (b, [' ' .. '~']) then
  //      Result := Result + b
    //  else
      Result := Result + '<' + IntToStr (ord (b)) + '>';
    end;
  a.Seek (x, soFromBeginning);
end;

function EncoderName (aType : integer) : string;
begin
  case aType of
    rfbEncodingRaw         : Result := 'Raw';
    rfbEncodingCopyRect    : Result := 'Copy Rect';
    rfbEncodingRRE         : Result := 'RRE';
    rfbEncodingCoRRE       : Result := 'CoRRE';
    rfbEncodingHextile     : Result := 'Hextile';
    rfbEncodingZLib        : Result := 'ZLib';
    rfbEncodingTight       : Result := 'Tight';
    rfbEncodingZLibHex     : Result := 'ZLib Hex';
    rfbEncodingUltra       : Result := 'Ultra';
    rfbEncodingTRLE        : Result := 'TRLE';
    rfbEncodingZRLE        : Result := 'ZRLE';
    rfbEncodingZYWRLE      : Result := 'ZYWRLE';
    rfbEncodingH264        : Result := 'H.264';
    rfbEncodingJPEG        : Result := 'JPEG';
    rfbEncodingJRLE        : Result := 'JRLE';
    rfbEncodingVAH264      : Result := 'VA H.264';
    rfbEncodingZRLE2       : Result := 'ZRLE2';
    rfbEncodingCursor      : Result := 'Cursor (pseudo)';
    rfbEncodingDeskTopSize : Result := 'DeskTopSize (pseudo)';
    else                     Result := 'Unknown (' + IntToStr (aType) + ')';
    end;
end;

function Card16 (a : string; Index : integer) : TCard16; inline;
begin
  if Index + 1 > Length (a) then
    Result := 0
  else
   Result := (ord (a[index]) * $100) + ord (a[index + 1]);
end;

function Card32 (a : string; Index : integer) : TCard32; inline;
begin
  if Index + 3 > Length (a) then
    Result := 0
  else
    Result := (ord (a[index]) * $1000000) + (ord (a[index + 1]) * $10000) +
              (ord (a[index + 2]) * $100) + ord (a[index + 3]);
end;

function Card8 (a : string; Index : integer) : TCard8; inline;
begin
 if Index > Length (a) then
    Result := 0
 else
  Result := ord (a[index]);
end;

function Str16 (Value : integer) : string; inline;
begin
  Result := Char (Value div $100) + Char (Value mod $100);
end;

function Str32 (Value : cardinal) : string; inline;
var
  i : integer;
  Reduce : cardinal;
begin
  Result := '';
  Reduce := Value;
  for i := 1 to 4 do
    begin
      Result := Char (Reduce mod $100) + Result;
      Reduce := Reduce div $100;
    end;
end;

function Str8 (Value : integer) : string; inline;
begin
  Result := AnsiChar (Value);
end;

function Swap16IfLE (s : TCard16) : TCard16; inline;
begin
  Result := ((s and $ff) shl 8) or ((s shl 8) and $ff);
end;

function  Swap32IfLE (l : TCard32) : TCard32; inline;
begin
  Result := ((l and $ff000000) shl 24) or
            ((l and $00ff0000) shl 8) or
            ((l and $0000ff00) shr 8) or
            ((l and $000000ff) shr 24);
end;

function Swap16 (Value : TCard16) : TCard16; inline;
begin
  Result := (lo (Value) << 8) + hi (Value);
end;

function Swap32 (Value : TCard32) : TCard32; inline;
var
  l, h : word;
begin
  l := lo (Value);
  h := hi (Value);
  Result := ((lo (l) shl 8) + hi (l)) shl 16;
  Result := Result + (lo (h) shl 8) + hi (h);
end;

end.

