program VNCTest;

{$mode objfpc}{$H+}

{$define use_tftp}
{$hints off}
{$notes off}
{$pointermath on}

uses
  RaspberryPi3,
  GlobalConfig,
  GlobalConst,
  GlobalTypes,
  Platform,
  Threads,
  SysUtils,
  Classes,
  Console,
  Services,
  FPWritePNG,
  FPReadPNG,
  Ultibo, uVNC,
{$ifdef use_tftp}
  uTFTP, Winsock2,
{$endif}
  Logging,
  FrameBuffer,
  HeapManager,
  uLog
  { Add additional units here };

var
  Console1, Console2, Console3 : TWindowHandle;
  ch : char;
  IPAddress : string;
  aVNC : TVNCServer;
  SysLogger : PLoggingDevice;
  Count : integer;
  Properties : TWindowProperties;
  DefFrameBuff : PFrameBufferDevice;
  ScreenWidth : LongWord;
  ScreenHeight : LongWord;

procedure SysLog (s : string);
begin
  LoggingOutput (s);
end;

procedure Log1 (s : string);
begin
  ConsoleWindowWriteLn (Console1, s);
end;

procedure Log2 (s : string);
begin
  ConsoleWindowWriteLn (Console2, s);
end;

procedure Log3 (s : string);
begin
  ConsoleWindowWriteLn (Console3, s);
end;

procedure Msg2 (Sender : TObject; s : string);
begin
  Log2 ('TFTP - ' + s);
end;

procedure WaitForSDDrive;
begin
  while not DirectoryExists ('C:\') do sleep (500);
end;

function WaitForIPComplete : string;
var
  TCP : TWinsock2TCPClient;
begin
  TCP := TWinsock2TCPClient.Create;
  Result := TCP.LocalAddress;
  if (Result = '') or (Result = '0.0.0.0') or (Result = '255.255.255.255') then
    begin
      while (Result = '') or (Result = '0.0.0.0') or (Result = '255.255.255.255') do
        begin
          sleep (1000);
          Result := TCP.LocalAddress;
        end;
    end;
  TCP.Free;
end;

procedure VNCPointer (Sender : TObject; Thread : TVNCThread; x, y : TCard16;
  BtnMask : TCard8);
begin
  ConsoleWindowSetXY (Console3, 1, 1);
  Consolewindowwrite (Console3, IntToStr (x) + ',' + IntToStr (y) + ' BTN MASK ' + BtnMask.ToHexString (2) + '      ');
  CursorSetState (true, x + Properties.X1, y + Properties.Y1, true);
end;

const
  ud : array[boolean] of string = ('UP', 'DOWN');

procedure VNCKey (Sender : TObject; Thread : TVNCThread; Key : TCard32;
  Down : boolean);
begin
  ConsoleWindowSetXY (Console3, 1, 2);
  Consolewindowwrite (Console3, 'KEY ' + IntToStr (Key) + ' ' + ud[Down] + '        ');
  if Down then
    begin
      if Key = 13 then
        ConsoleWindowWriteln (Console1, '')
      else
        ConsoleWindowWrite (Console1, Char (Key));
    end;
end;

procedure VNCRect (Sender : TObject; r : Classes.TRect);
begin
  Count := Count + 1;
  ConsoleWindowSetXY (Console3, 1, 3);
  ConsoleWindowWrite (Console3, 'FRAME ' + IntToStr (Count) + '   ');
  aVNC.Canvas.Copy (DefFrameBuff, Properties.X1, Properties.Y1);
end;

procedure VNCSize (Sender : TObject; var x, y : integer);
begin

  x := Properties.X2 - Properties.X1;
  y := Properties.Y2 - Properties.Y1;
//  Log1 ('x = ' + x.ToString + ' y = ' + y.ToString);
end;

procedure CreateCursor;
var
  Row : LongWord;
  Col : LongWord;
  Offset : LongWord;
  Size : LongWord;
  Cursor : PLongWord;
  Address : LongWord;
begin
  Size := 32 * 32 * 4;
  case BoardGetType of
    BOARD_TYPE_RPIA, BOARD_TYPE_RPIB,
    BOARD_TYPE_RPIA_PLUS, BOARD_TYPE_RPIB_PLUS,
    BOARD_TYPE_RPI_ZERO :
      begin
        Cursor := AllocSharedMem (Size);
      end;
    BOARD_TYPE_RPI2B, BOARD_TYPE_RPI3B :
      begin
        Cursor := AllocNoCacheMem (Size);
      end;
    else
      begin
        Cursor := nil;
      end;
    end;
  if Cursor <> nil then
    begin
      Offset := 0;
      for Row := 0 to 31 do
        begin
          for Col := 0 to 31 do
            begin
              if ((Col and 8) xor (Row and 8)) <> 0 then
                begin
                  Cursor[Col + Offset] := $a0ff0000;
                end
              else
                begin
                  Cursor[Col + Offset] := $a00000ff;
                end;
            end;
          Inc (Offset, 32);
       end;
     Address := PhysicalToBusAddress (Cursor);
     CursorSetInfo (32, 32, 0, 0, Pointer (Address), Size);
     FreeMem (Cursor);
   end;
end;

begin
  Console2 := ConsoleWindowCreate (ConsoleDeviceGetDefault, CONSOLE_POSITION_TOPRIGHT, false);
  Console3 := ConsoleWindowCreate (ConsoleDeviceGetDefault, CONSOLE_POSITION_BOTTOMRIGHT, true);
  Console1 := ConsoleWindowCreate (ConsoleDeviceGetDefault, CONSOLE_POSITION_LEFT, false);
  SysLogger := LoggingDeviceFindByType (LOGGING_TYPE_SYSLOG);
  SysLogLoggingSetTarget (SysLogger, '192.168.0.255');
  LoggingDeviceSetDefault (SysLogger);
  SetLogProc (@SysLog);

  DefFrameBuff := FramebufferDeviceGetDefault;
  ConsoleWindowGetProperties (Console1, @Properties);

  Log1 ('VNC Server Test 16.');
  Log1 ('2021 pjde.');
  Log3 ('');
  WaitForSDDrive;
  Log1 ('SD Drive Ready.');
  IPAddress := WaitForIPComplete;
  Log1 ('Run VNC Viewer and point to ' + IPAddress);

{$ifdef use_tftp}
  Log2 ('TFTP - Enabled.');
  Log2 ('TFTP - Syntax "tftp -i ' + IPAddress + ' put kernel7.img"');
  SetOnMsg (@Msg2);
  Log2 ('');
{$endif}

  if FramebufferGetPhysical (ScreenWidth, ScreenHeight) = ERROR_SUCCESS then
    Log2 ('Screen is ' + IntToStr (ScreenWidth) + ' pixels wide by ' + IntToStr (ScreenHeight) + ' pixels high');

  CreateCursor;
  Count := 0;
  aVNC := TVNCServer.Create;
  aVNC.OnKey := @VNCKey;
  aVNC.OnPointer := @VNCPointer;
  aVNC.OnGetRect := @VNCRect;
  aVNC.OnGetSize := @VNCSize;
  aVNC.InitCanvas;
  aVNC.Canvas.Fill (COLOR_BLACK);
  aVNC.Title := 'Ultibo VNC Server Mk II';
  aVNC.Active := true;
  ThreadHalt (0);
end.

