(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Mnewdynarray;

TYPE
  Array = POINTER TO ARRAY OF ARRAY OF INTEGER;

PROCEDURE P0;
  VAR
    p : Array;
BEGIN
  NEW(p, 3, 4);
END P0;

END Mnewdynarray.
