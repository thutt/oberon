(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test code generation for conditional set instructions.
 *)
MODULE CTConditionCode;
IMPORT Console;

VAR
  v : LONGINT;


PROCEDURE LessThan(b : BOOLEAN);
BEGIN
  Console.Str("LessThan ");
  Console.Bool(b);
  Console.Ln;
END LessThan;


PROCEDURE Test*;
BEGIN
  LessThan(v < 0);
  LessThan(v < 100);
  LessThan(v >= 0);
END Test;
BEGIN
  v := 10;
END CTConditionCode. (* 'Icoc' *)
