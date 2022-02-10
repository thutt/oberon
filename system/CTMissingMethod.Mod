(* Copyright (c) 2022 Logic Magicians Software *)
MODULE CTMissingMethod;
IMPORT Console;
TYPE
  Part = POINTER TO ARRAY OF CHAR;
  Basic* = POINTER TO BasicDesc;
  BasicDesc* = RECORD
  END;

TYPE
  Posix*     = POINTER TO PosixDesc;
  PosixDesc* = RECORD (BasicDesc)
  END;

PROCEDURE (self : Posix) Initialize*(path : ARRAY OF CHAR);
END Initialize;


PROCEDURE Create*(path : ARRAY OF CHAR) : Basic;
  VAR
    pathname : Posix;
BEGIN
  RETURN pathname;
END Create;

PROCEDURE Test*;
 VAR p : Basic;
BEGIN
  p := Create("/");
  p.Initialize("test");
END Test;


END CTMissingMethod;
