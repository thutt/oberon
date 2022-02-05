(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test code generation for SYSTEM.ROT.
 *)
MODULE CTRotate;
IMPORT SYSTEM, Console;


PROCEDURE Rotate(value  : LONGINT;
                 expect : LONGINT;
                 shift  : INTEGER);
  VAR
    result : LONGINT;
BEGIN
  result := SYSTEM.ROT(value, shift);
  IF result # expect THEN
    Console.Str("Rotate ");
    Console.Hex(value);
    Console.Str(" by ");
    Console.Hex(shift);
    Console.Str(" expected ");
    Console.Hex(expect);
    Console.Str(" got ");
    Console.Hex(result);
    Console.Ln;
  END;
END Rotate;

PROCEDURE Test*;
BEGIN
  Rotate(80000000H, 1, 1);
  Rotate(80000000H, 40000000H, -1);

  Rotate(80004000H, 00008001H, 1);
  Rotate(80004000H, 40002000H, 31);
  Rotate(80004000H, 40002000H, -1);
END Test;


END CTRotate.
