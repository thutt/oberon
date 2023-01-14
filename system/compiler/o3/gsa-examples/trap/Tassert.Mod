(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Tassert;

PROCEDURE P0(x, y : BOOLEAN);
BEGIN
  ASSERT(x & y, 1024);
END P0;

PROCEDURE P1(x, y : BOOLEAN);
BEGIN
  ASSERT(x OR y);
END P1;

END Tassert.
