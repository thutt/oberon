(* Copyright (c) 2021 Logic Magicians Software
 *)
MODULE CTDynArrLength;
PROCEDURE Test*;
VAR
  p : POINTER TO ARRAY OF INTEGER;
  v : LONGINT;

BEGIN
  p := NIL;
  v := LEN(p^);
END Test;
END CTDynArrLength.
