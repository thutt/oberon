(* Copyright (c) 2021 Logic Magicians Software
 *)
MODULE CTOOBWrite;
IMPORT SYSTEM;

PROCEDURE Test*;
VAR
  v : LONGINT;
BEGIN
  v := 0;
  (* Valid addresses cannot have upper two bits set.
   * The upper two bits are used as sentinel values by the GC.
   *)
  SYSTEM.MEMW(0C0000000H, SIZE(LONGINT), v);
END Test;

END CTOOBWrite.
