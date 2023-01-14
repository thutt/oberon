(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Hputreg;
IMPORT SYSTEM;

PROCEDURE P0;
  VAR
    v : LONGINT;
BEGIN
  SYSTEM.PUTREG(3, v);
END P0;

END Hputreg.
