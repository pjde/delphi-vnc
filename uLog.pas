unit uLog;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TLogProc = procedure (s : string);

var
  FLogProc : TLogProc = nil;

procedure SetLogProc (lp : TLogProc);
procedure Log (s : string);

implementation

procedure SetLogProc (lp : TLogProc);
begin
  FLogProc := lp;
end;

procedure Log (s : string);
begin
  if Assigned (FLogProc) then FLogProc (s);
end;

end.

