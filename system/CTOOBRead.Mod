(* Copyright (c) 2021 Logic Magicians Software
 *)
MODULE CTOOBRead;
IMPORT SYSTEM;

PROCEDURE Test*;
VAR
  v : LONGINT;
BEGIN
  (* Valid addresses cannot have upper two bits set.
   * The upper two bits are used as sentinel values by the GC.
   *)
  SYSTEM.MEMR(0C0000000H, SIZE(LONGINT), v);
END Test;

END CTOOBRead.
