(* Copyright (c) 2022 Logic Magicians Software
 *)
MODULE CTFor;
IMPORT Console;

PROCEDURE TestShortintFor;
  VAR
    i : SHORTINT;
BEGIN
  FOR i := 0 TO 10 DO
    Console.Int(i, 5);
    Console.Ln;
  END;
END TestShortintFor;

PROCEDURE TestIntegerFor;
  VAR
    i : INTEGER;
BEGIN
  FOR i := 0 TO 10 DO
    Console.Int(i, 5);
    Console.Ln;
  END;
END TestIntegerFor;


PROCEDURE TestLongintFor;
  VAR
    i : LONGINT;
BEGIN
  FOR i := 0 TO 10 DO
    Console.Int(i, 5);
    Console.Ln;
  END;
END TestLongintFor;

PROCEDURE Test*;
BEGIN
  TestShortintFor;
  TestIntegerFor;
  TestLongintFor;
END Test;

END CTFor.
