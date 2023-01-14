(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Mnewarray;

TYPE
  Array = POINTER TO ARRAY 100 OF INTEGER;

PROCEDURE P0;
  VAR
    p : Array;
BEGIN
  NEW(p);
  p[5] := 151;
END P0;

END Mnewarray.
