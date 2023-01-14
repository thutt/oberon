(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Tiguard;
TYPE
  Base = POINTER TO BaseDesc;
  BaseDesc = RECORD x : INTEGER; END;
  Ext = POINTER TO ExtDesc;
  ExtDesc = RECORD (BaseDesc) y : INTEGER; END;

PROCEDURE P0(b : Base);
  VAR
    e : Ext;
BEGIN
  b^ := e^;
END P0;

END Tiguard.
