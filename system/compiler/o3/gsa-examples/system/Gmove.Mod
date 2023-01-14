(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Gmove;
IMPORT SYSTEM;

PROCEDURE P0;
  VAR
    b : SYSTEM.PTR;
BEGIN
  SYSTEM.MOVE(100, 200, 1024);
END P0;
END Gmove.
