(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Twith;
TYPE
  Base = POINTER TO BaseDesc;
  BaseDesc = RECORD x : INTEGER; END;
  Ext = POINTER TO ExtDesc;
  ExtDesc = RECORD (BaseDesc) y : INTEGER; END;

PROCEDURE P0(VAR b : Base) : BOOLEAN;
BEGIN
  WITH b:Ext DO
  END;
END P0;

END Twith.
