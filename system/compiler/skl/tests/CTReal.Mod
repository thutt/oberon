(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test floating point operations.
 *)
MODULE CTReal;
  IMPORT Console;

PROCEDURE AbsLongReal(v : LONGREAL);
VAR n : LONGREAL;
BEGIN
  n := ABS(v);
  Console.Str("AbsLongReal arg: ");
  Console.LReal(v, 20);
  Console.Str(" abs: ");
  Console.LReal(n, 20);
  Console.Ln;
END AbsLongReal;

PROCEDURE AbsReal(v : REAL);
VAR n : REAL;  
BEGIN
  n := ABS(v);
  Console.Str("AbsReal arg: ");
  Console.Real(v, 10);
  Console.Str(" abs: ");
  Console.Real(n, 10);
  Console.Ln;
END AbsReal;

PROCEDURE Test*;
BEGIN
  AbsReal(-1.3);
  AbsLongReal(-10.3);
END Test;

END CTReal.
