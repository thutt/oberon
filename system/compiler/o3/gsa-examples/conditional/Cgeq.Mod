(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Cgeq;

PROCEDURE P0(x, y : INTEGER) : BOOLEAN;
BEGIN
  RETURN x >= y;
END P0;

PROCEDURE P1(x, y : ARRAY OF CHAR) : BOOLEAN;
BEGIN
  RETURN x >= y;
END P1;

END Cgeq.
