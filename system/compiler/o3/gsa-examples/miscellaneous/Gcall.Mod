(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Gcall;

PROCEDURE P0(x : INTEGER; VAR y : INTEGER) : INTEGER;
BEGIN
END P0;

PROCEDURE P1; VAR x : INTEGER;
BEGIN
  x := P0(151, x);
END P1;
END Gcall.
