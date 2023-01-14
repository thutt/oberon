(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Hmemw;
IMPORT SYSTEM;

PROCEDURE P0;
  VAR
    v : LONGINT;
BEGIN
  SYSTEM.MEMW(3, 10, v);
END P0;

END Hmemw.
