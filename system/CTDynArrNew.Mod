(* Copyright (c) 2021 Logic Magicians Software
 *)
MODULE CTDynArrNew;
IMPORT Kernel, Console;

VAR
  p : POINTER TO ARRAY OF ARRAY OF ARRAY OF INTEGER;

PROCEDURE Allocate;
BEGIN
  NEW(p, 10H, 20H, 30H);
END Allocate;

PROCEDURE Set(x, y, z : INTEGER; value : INTEGER);
BEGIN
  p[x][y][z] := value;
END Set;

PROCEDURE Len0() : LONGINT;
BEGIN
  RETURN LEN(p^, 0);
END Len0;

PROCEDURE Len1() : LONGINT;
BEGIN
  RETURN LEN(p^, 1);
END Len1;

PROCEDURE Len2() : LONGINT;
BEGIN
  RETURN LEN(p^, 2);
END Len2;

PROCEDURE Test*;
BEGIN
  Allocate;
  Console.Str("Allocated array: ");
  Console.Hex(Len0());
  Console.Str(", ");
  Console.Hex(Len1());
  Console.Str(", ");
  Console.Hex(Len2());
  Console.Ln;
END Test;
END CTDynArrNew.
