(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Tindex;

PROCEDURE P0;
  VAR
    a : ARRAY 10 OF INTEGER;
    x : INTEGER;
BEGIN
  x := 10;
  x := a[x];
END P0;

END Tindex.
