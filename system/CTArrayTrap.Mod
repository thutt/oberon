(* Copyright (c) 2021 Logic Magicians Software
 *)
MODULE CTArrayTrap;
IMPORT Console;

CONST
  FnLength* = 256; (* maximum pathname length (FILENAME_MAX) *)


TYPE
  Filename* = ARRAY FnLength OF CHAR;

TYPE
  PathInfo* = RECORD
    path : Filename;
    name : Filename;
    ext  : Filename;
  END;

PROCEDURE Split*(pathname : ARRAY OF CHAR; VAR info : PathInfo);
  VAR extPos, namePos, pathPos : INTEGER;

  PROCEDURE ReverseBuf(VAR in      : Filename;
                       nofChar : INTEGER;
                       VAR out     : Filename);
    VAR
      i : INTEGER;
  BEGIN
    i := 0;
    REPEAT
      DEC(nofChar);
      out[i] := in[nofChar];
      INC(i);
    UNTIL nofChar = 0;
  END ReverseBuf;

  (* ext <=> filename extension w/ '.' *)
  (* returns position where extension begins (0..LEN(Filename)] *)
  PROCEDURE GetExtension(VAR pathname : ARRAY OF CHAR;
                         VAR ext      : Filename;
                         VAR extStart : INTEGER);
    VAR
      buf : Filename;
      i, j, len : INTEGER;
      ch : CHAR;
  BEGIN
    len := 0;
    LOOP
      IF (len >= LEN(pathname) - 1) OR (pathname[len] = 0X) THEN
        EXIT;
      END;
      INC(len);
    END;
    
    (* inv: len <=> (index of 0X) OR (LEN(pathname) - 1) *)
    i := len;
    buf[0] := 0X; (* 0X-terminated when reversed *)
    j := 1;
    LOOP
      ch := pathname[i];
      IF ch = '/' THEN
        EXIT;
      END;
      buf[j] := ch;
      INC(j);
      DEC(i);
      IF (i < 0) OR (j >= LEN(buf)) OR (ch = '.') THEN
        EXIT;
      END;
    END; (* path separator before a '.' => no extension *)

    (* inv: (i < 0) OR (j = index of '.', '/' *)
    (* inv: j <=> index of last char in buf + 1 *)
    IF (i >= 0) & (ch = '.') THEN
      ReverseBuf(buf, j, ext);
      extStart := i + 1;
    ELSE
      ext[0] := 0X;
      extStart := len;
    END;
  END GetExtension;


  (* extIndex <=> index of first character of file
   *  extension (0..LEN(Filename)] *)
  (* ext <=> filename (no path separators)  *)
  (* returns index of first character of filename (0..LEN(Filename)])
   * (0 => no path in pathname, ~0 => returnwd value <=>
   *                                  path separator index) *)
  PROCEDURE GetFilename(    extIndex      : INTEGER;
                            VAR name          : Filename;
                            VAR filenameStart : INTEGER);
    VAR
      buf : Filename;
      i, j, k : INTEGER;
      ch : CHAR;
  BEGIN
    i := extIndex - 1;
    ch := ' ';
    buf[0] := 0X; (* 0X-terminated when reversed *)
    j := 1;
    LOOP
      IF (i < 0) OR (pathname[i] = '/') OR (j >= LEN(buf)) THEN
        EXIT;
      END;
      ch := pathname[i];
      buf[j] := ch;
      DEC(i);
      INC(j);
    END;

    (* inv: (i < 0) OR (i = index of '/') *)
    (* inv: j <=> index of last char in buf + 1 *)
    ReverseBuf(buf, j, name);
    IF i >= 0 THEN (* path separator found *)
      filenameStart := i + 1;
    ELSE (* no path separator found *)
      filenameStart := 0;
    END;
  END GetFilename;


  PROCEDURE GetPath(nameStart     : INTEGER;
                    VAR path      : Filename;
                    VAR pathStart : INTEGER);
    VAR
      buf : Filename;
      nofSep, i, k, len : INTEGER;
  BEGIN
    ASSERT(nameStart < LEN(pathname));
    path[0] := 0X;
    len := LEN(path);
    k := 0;
    pathStart := 0;
    i := 0;
    WHILE (k < nameStart) & (k < len) DO
      path[i] := pathname[k];
      INC(k);
      INC(i);
    END;
    (* inv: k = 1 beyond last character stored *)
    IF i >= len THEN
      k := len - 1;
    END;
    path[i] := 0X;
  END GetPath;

BEGIN
  GetExtension(pathname, info.ext, extPos);
  GetFilename(extPos, info.name, namePos); (* inv: a filename must exist *)
  GetPath(namePos, info.path, pathPos); (* inv: pathname ends with '/' *)
  Console.Str("Split: path='");
  Console.Str(info.path);
  Console.Str("'  name='");
  Console.Str(info.name);
  Console.Str("'  ext='");
  Console.Str(info.ext);
  Console.Str("'");
  Console.Ln;
END Split;



PROCEDURE Test*;
VAR
  p : ARRAY 15 OF INTEGER;
  v : LONGINT;
  info : PathInfo;
BEGIN
  Split(".DiagnosticOutput", info);
  v := 128;
  p[14] := 0;
END Test;

END CTArrayTrap.
