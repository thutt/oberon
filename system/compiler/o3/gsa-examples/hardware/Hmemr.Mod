(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Hmemr;
IMPORT SYSTEM;

PROCEDURE P0;
  VAR
    v : LONGINT;
BEGIN
  SYSTEM.MEMR(3, 10, v);
END P0;

END Hmemr.
