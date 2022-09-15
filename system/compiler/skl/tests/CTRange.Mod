(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test code generation for range checking.
 *)
MODULE CTRange;

PROCEDURE ShortInt(x : INTEGER);
  VAR s : SHORTINT;
BEGIN
  s := SHORT(x);
END ShortInt;

PROCEDURE Integer(x : LONGINT);
  VAR s : INTEGER;
BEGIN
  s := SHORT(x);
END Integer;

PROCEDURE Set(x, y : INTEGER);
  VAR s : SET;
BEGIN
  s := { x..y };
END Set;

PROCEDURE Real(x : LONGREAL);
  VAR s : REAL;
BEGIN
  s := SHORT(x);
END Real;


PROCEDURE RealToInt(x : LONGREAL);
  VAR s : LONGINT;
BEGIN
  s := ENTIER(x);
END RealToInt;


PROCEDURE Test*;
BEGIN
  Real(10.10);
  RealToInt(10.10);
  ShortInt(1);
  Integer(10);
  Set(10, 20);
  ShortInt(-192);
END Test;

END CTRange.
