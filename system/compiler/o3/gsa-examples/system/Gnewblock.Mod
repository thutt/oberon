(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Gnewblock;
IMPORT SYSTEM;

PROCEDURE P0;
  VAR
    b : SYSTEM.PTR;
BEGIN
  SYSTEM.NEW(b, 1024);
END P0;
END Gnewblock.
