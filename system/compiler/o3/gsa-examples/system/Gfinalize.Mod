(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Gfinalize;
IMPORT SYSTEM;

TYPE
  Base = POINTER TO BaseDesc;
  BaseDesc = RECORD
  END;

PROCEDURE Finalize(b : Base);
BEGIN
END Finalize;

PROCEDURE P0;
BEGIN
  SYSTEM.FINALIZE(BaseDesc, Finalize);
END P0;
END Gfinalize.
