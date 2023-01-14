(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Hgetreg;
IMPORT SYSTEM;

PROCEDURE P0;
  VAR
    v : LONGINT;
BEGIN
  SYSTEM.GETREG(3, v);
END P0;

END Hgetreg.
