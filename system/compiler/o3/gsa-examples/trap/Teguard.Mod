(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Teguard;
TYPE
  Base = POINTER TO BaseDesc;
  BaseDesc = RECORD x : INTEGER; END;
  Ext = POINTER TO ExtDesc;
  ExtDesc = RECORD (BaseDesc) y : INTEGER; END;

PROCEDURE P0(VAR b : Base) : BOOLEAN;
BEGIN
  RETURN b{Ext}.y = 0;
END P0;

END Teguard.
