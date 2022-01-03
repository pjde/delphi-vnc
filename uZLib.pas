unit uZLib;

{$mode objfpc}{$H+}

interface

type

  TAlloc = function (AppData : pointer; Items, Size : integer) : pointer; cdecl;
  TFree = procedure (AppData, Block : pointer); cdecl;

  {$PACKRECORDS C}

  TZStreamRec = record // packed record
    next_in : pointer;     // next input byte
    avail_in : integer;    // number of bytes available at next_in
    total_in : integer;    // total nb of input bytes read so far
    next_out : pointer;    // next output byte should be put here
    avail_out : integer;   // remaining free space at next_out
    total_out : integer;   // total nb of bytes output so far
    msg : PChar;           // last error message, NULL if no error
    internal : pointer;    // not visible by applications
    zalloc : TAlloc;       // used to allocate the internal state
    zfree : TFree;         // used to free the internal state
    opaque : pointer;
    data_type : integer;   // best guess about the data type: ascii or binary
    adler : cardinal;      // adler32 value of the uncompressed data
    reserved : cardinal;   // reserved for future use
  end;

const
  zlib_version = '1.2.11';

const
  Z_NO_FLUSH             = 0;
  Z_PARTIAL_FLUSH        = 1;
  Z_SYNC_FLUSH           = 2;
  Z_FULL_FLUSH           = 3;
  Z_FINISH               = 4;

  Z_OK                   = 0;
  Z_STREAM_END           = 1;
  Z_NEED_DICT            = 2;
  Z_ERRNO                = -1;
  Z_STREAM_ERROR         = -2;
  Z_DATA_ERROR           = -3;
  Z_MEM_ERROR            = -4;
  Z_BUF_ERROR            = -5;
  Z_VERSION_ERROR        = -6;

  Z_NO_COMPRESSION       = 0;
  Z_BEST_SPEED           = 1;
  Z_BEST_COMPRESSION     = 9;
  Z_DEFAULT_COMPRESSION  = -1;

  Z_FILTERED             = 1;
  Z_HUFFMAN_ONLY         = 2;
  Z_DEFAULT_STRATEGY     = 0;

  Z_BINARY               = 0;
  Z_ASCII                = 1;
  Z_UNKNOWN              = 2;

  Z_DEFLATED             = 8;

  _z_errmsg: array [0..9] of PChar = (
    'need dictionary',      // Z_NEED_DICT      (2)
    'stream end',           // Z_STREAM_END     (1)
    '',                     // Z_OK             (0)
    'file error',           // Z_ERRNO          (-1)
    'stream error',         // Z_STREAM_ERROR   (-2)
    'data error',           // Z_DATA_ERROR     (-3)
    'insufficient memory',  // Z_MEM_ERROR      (-4)
    'buffer error',         // Z_BUF_ERROR      (-5)
    'incompatible version', // Z_VERSION_ERROR  (-6)
    ''
  ); public name 'z_errmsg';

// deflate compresses data

function deflateInit (var strm : TZStreamRec; level : integer) : integer;
function deflateInit_ (var strm : TZStreamRec; level : integer; version : PChar;
  recsize : integer) : integer; cdecl; external;
function deflate (var strm : TZStreamRec; flush : integer) : integer; cdecl; external;
function deflateEnd (var strm : TZStreamRec) : integer; cdecl; external;

// inflate decompresses data
function inflateInit (var strm : TZStreamRec) : integer;
function inflateInit_ (var strm : TZStreamRec; version : PChar; recsize : integer) : integer; cdecl; external;
function inflate (var strm : TZStreamRec; flush : integer) : integer; cdecl; external;
function inflateEnd (var strm : TZStreamRec) : integer; cdecl; external;
function inflateReset (var strm : TZStreamRec) : integer; cdecl; external;

// adler
function adler32 (adler : integer; buf : PChar; len : integer) : integer; cdecl; external;

implementation

{$LinkLib zlib}

function deflateInit (var strm : TZStreamRec; level : integer) : integer;
begin
  Result := deflateInit_ (strm, level, zlib_version, sizeof (TZStreamRec));
end;


function inflateInit (var strm : TZStreamRec) : integer;
begin
  Result := inflateInit_ (strm, zlib_version, sizeof (TZStreamRec));
end;

procedure _memset (P : pointer; B: Byte; count : integer); cdecl; public name 'memset';
begin
  FillChar (P^, count, B);
end;

procedure _memcpy (dest, source : pointer; count : integer); cdecl; public name 'memcpy';
begin
  Move (source^, dest^, count);
end;

function zcalloc (AppData : pointer; Items, Size : integer) : pointer; cdecl; public name 'zcalloc';
begin
  GetMem (Result, Items * Size);
end;

procedure zcfree (AppData, Block : pointer); cdecl; public name 'zcfree';
begin
  FreeMem (Block);
end;

end.



